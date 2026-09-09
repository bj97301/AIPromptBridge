import CryptoKit
import Foundation

struct SkillTarget {
    let id: String
    var title: String
    let root: URL
    var destination: URL { root.appendingPathComponent("aipromptbridge", isDirectory: true) }

    init(id: String = "folder", title: String, root: URL) {
        self.id = id; self.title = title; self.root = root
    }
}

struct SkillInstallResult {
    let target: SkillTarget
    let state: String
    let detail: String
}

/// Installs only this app's skill. Existing customizations are never overwritten.
final class SkillInstaller {
    let home: URL
    let environment: [String: String]
    let payload: URL
    let app: URL
    private let fm = FileManager.default
    private let manifestName = ".aipromptbridge-install.json"

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         payload: URL, app: URL) {
        self.home = home.standardizedFileURL
        self.environment = environment
        self.payload = payload
        self.app = app
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "AIPromptBridge.SkillInstaller", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    func discover() -> (targets: [SkillTarget], notes: [String]) {
        var targets = [SkillTarget(id: "shared", title: "Codex, Cursor, ChatGPT desktop, OpenCode & shared agents",
                                   root: home.appendingPathComponent(".agents/skills"))]
        var notes: [String] = []
        func configuredHome(_ value: String?, context: String, fallback: URL) -> URL? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
            let expanded = value == "~" ? home.path : value.hasPrefix("~/") ? home.appendingPathComponent(String(value.dropFirst(2))).path : value
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            // Provider config is not a license to scatter files outside this account.
            guard expanded.hasPrefix("/"), url.path.hasPrefix(home.path + "/") || url == home else {
                notes.append("\(context): custom home is outside this account or is relative. Use Choose skills folder or skills install --folder to select it explicitly.")
                return nil
            }
            return url
        }
        let claudeDefault = home.appendingPathComponent(".claude")
        if let config = configuredHome(environment["CLAUDE_CONFIG_DIR"], context: "Claude Code", fallback: claudeDefault) {
            targets.append(SkillTarget(id: "claude", title: "Claude Code", root: config.appendingPathComponent("skills")))
        }
        // T3 uses its providers' own skill loaders, not a separate T3 skill format.
        for relative in [".t3/userdata/settings.json", ".t3/dev/settings.json"] {
            let settings = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: settings.path) else { continue }
            do {
                let size = (try fm.attributesOfItem(atPath: settings.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size <= 2_000_000 else { throw error("settings file is too large") }
                guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else {
                    throw error("settings is not a JSON object")
                }
                guard let providers = object["providerInstances"] as? [String: Any] else { continue }
                for key in providers.keys.sorted() {
                    guard let provider = providers[key] as? [String: Any], provider["enabled"] as? Bool != false,
                          provider["driver"] as? String == "claudeAgent" else { continue }
                    let config = provider["config"] as? [String: Any] ?? [:]
                    let env = provider["environment"] as? [[String: Any]] ?? []
                    let envHome = env.first(where: { $0["name"] as? String == "CLAUDE_CONFIG_DIR" })?["value"] as? String
                    let custom = (config["homePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = custom?.isEmpty == false ? custom : (envHome ?? environment["CLAUDE_CONFIG_DIR"])
                    if let configHome = configuredHome(value, context: "T3 Code \(key)", fallback: claudeDefault) {
                        let profile = relative == ".t3/userdata/settings.json" ? "main" : "dev"
                        targets.append(SkillTarget(id: "t3:\(profile):\(key)", title: "T3 Code: \(key)", root: configHome.appendingPathComponent("skills")))
                    }
                }
            } catch { notes.append("Could not inspect \(relative): \(error.localizedDescription)") }
        }
        var unique: [SkillTarget] = []
        for target in targets {
            let canonical = target.root.resolvingSymlinksInPath().standardizedFileURL
            if let index = unique.firstIndex(where: { $0.root.resolvingSymlinksInPath().standardizedFileURL == canonical }) {
                unique[index].title += " / " + target.title
            } else { unique.append(target) }
        }
        return (unique, notes)
    }

    private func files(at directory: URL) throws -> [String: Data] {
        let rootType = try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType
        guard rootType == .typeDirectory else { throw error("Destination is not an ordinary folder; it was left unchanged.") }
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        var traversalError: Error?
        guard let entries = fm.enumerator(at: canonical, includingPropertiesForKeys: nil, errorHandler: { _, problem in
            traversalError = problem
            return false
        }) else { throw error("Cannot inspect the skill folder.") }
        var result: [String: Data] = [:]
        for case let file as URL in entries {
            let type = try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeRegular else { throw error("Skill contains a link or special file; it was left unchanged.") }
            if type == .typeRegular {
                let normalized = file.resolvingSymlinksInPath().standardizedFileURL.path
                guard normalized.hasPrefix(canonical.path + "/") else { throw error("Skill file escaped its folder.") }
                let relative = String(normalized.dropFirst(canonical.path.count + 1))
                result[relative] = try Data(contentsOf: file)
            }
        }
        if let traversalError { throw traversalError }
        return result
    }

    private func hashes(_ files: [String: Data]) -> [String: String] {
        files.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    func install(_ target: SkillTarget) -> SkillInstallResult {
        let destination = target.destination
        var stage: URL?
        do {
            var expected = try files(at: payload)
            guard expected["SKILL.md"] != nil, expected["scripts/aipromptbridge"] != nil,
                  expected["references/LICENSE"] != nil, expected["references/RISK_NOTICE.md"] != nil else {
                throw error("Bundled skill is incomplete. Rebuild the app.")
            }
            expected["scripts/app-location.json"] = try JSONSerialization.data(withJSONObject: ["appPath": app.path], options: [.prettyPrinted, .sortedKeys])
            let exists = (try? fm.attributesOfItem(atPath: destination.path)) != nil
            if exists {
                var previous = try files(at: destination)
                let manifest = previous.removeValue(forKey: manifestName)
                guard let manifest,
                      let object = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
                      object["owner"] as? String == "io.github.bj97301.aipromptbridge",
                      let recorded = object["files"] as? [String: String], hashes(previous) == recorded else {
                    return SkillInstallResult(target: target, state: "Skipped", detail: "Existing or edited skill preserved. Choose another skills folder, or move your copy before installing.")
                }
                if previous == expected { return SkillInstallResult(target: target, state: "Already installed", detail: destination.path) }
            }
            try fm.createDirectory(at: target.root, withIntermediateDirectories: true)
            let staging = target.root.appendingPathComponent(".aipromptbridge-stage-" + UUID().uuidString)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            stage = staging
            for (relative, bytes) in expected {
                let file = staging.appendingPathComponent(relative)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: file, options: .atomic)
            }
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.appendingPathComponent("scripts/aipromptbridge").path)
            let manifest = try JSONSerialization.data(withJSONObject: ["owner": "io.github.bj97301.aipromptbridge", "files": hashes(expected)], options: [.sortedKeys])
            try manifest.write(to: staging.appendingPathComponent(manifestName), options: .atomic)
            if exists {
                // Recheck immediately before replacement, including edits made during staging.
                var current = try files(at: destination)
                let currentManifest = current.removeValue(forKey: manifestName)
                guard let currentManifest,
                      let object = try JSONSerialization.jsonObject(with: currentManifest) as? [String: Any],
                      object["owner"] as? String == "io.github.bj97301.aipromptbridge",
                      let recorded = object["files"] as? [String: String], hashes(current) == recorded else {
                    throw error("Skill changed during installation; it was left unchanged.")
                }
                let backups = home.appendingPathComponent("Library/Application Support/AIPromptBridge/Skill Backups")
                try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let backup = backups.appendingPathComponent(UUID().uuidString)
                try fm.moveItem(at: destination, to: backup)
                do { try fm.moveItem(at: staging, to: destination) }
                catch {
                    do { try fm.moveItem(at: backup, to: destination) }
                    catch { throw self.error("Restore failed. Your previous skill is preserved at \(backup.path).") }
                    throw error
                }
                // Keep an update backup. It also preserves empty folders added by the user.
                return SkillInstallResult(target: target, state: "Updated", detail: "\(destination.path)\nPrevious copy: \(backup.path)")
            }
            try fm.moveItem(at: staging, to: destination)
            return SkillInstallResult(target: target, state: "Installed", detail: destination.path)
        } catch {
            if let stage { try? fm.removeItem(at: stage) }
            return SkillInstallResult(target: target, state: "Failed", detail: error.localizedDescription)
        }
    }
}
