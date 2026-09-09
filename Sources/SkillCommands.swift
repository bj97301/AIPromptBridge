import Foundation
import CoreFoundation

/// Setup commands share the GUI installer and do not enable computer control.
final class SkillCommands {
    static let operations: Set<String> = ["skills.list", "skills.install", "skills.export"]
    let installer: SkillInstaller

    init(installer: SkillInstaller) { self.installer = installer }

    private func invalid(_ message: String) -> [String: Any] {
        ["status": "invalid_request", "message": message]
    }

    private func describe(_ target: SkillTarget) -> [String: Any] {
        ["id": target.id, "title": target.title, "skills_folder": target.root.path,
         "destination": target.destination.path]
    }

    func handle(_ request: [String: Any]) -> [String: Any] {
        guard let op = request["op"] as? String, Self.operations.contains(op) else {
            return invalid("Unknown skill command.")
        }
        var environment = installer.environment
        if let raw = request["claude_config_dir"] {
            guard let value = raw as? String, value.utf8.count <= 4096, !value.contains("\0") else {
                return invalid("CLAUDE_CONFIG_DIR must be a path of at most 4096 bytes.")
            }
            environment["CLAUDE_CONFIG_DIR"] = value
        }
        let current = SkillInstaller(home: installer.home, environment: environment,
                                     payload: installer.payload, app: installer.app)
        if op == "skills.export" {
            do {
                let url = current.payload.deletingLastPathComponent().appendingPathComponent("aipromptbridge-skill.zip")
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
                guard let size, size.intValue > 0, size.intValue <= 8 * 1024 * 1024 else {
                    return ["status": "export_failed", "message": "Bundled skill ZIP is empty or too large. Rebuild the app."]
                }
                let data = try Data(contentsOf: url)
                return ["status": "ok", "filename": "aipromptbridge-skill.zip", "archive_base64": data.base64EncodedString()]
            } catch {
                return ["status": "export_failed", "message": "Bundled skill ZIP is unavailable. Rebuild the app."]
            }
        }
        let discovery = current.discover()
        if op == "skills.list" {
            return ["status": "ok", "targets": discovery.targets.map(describe), "notes": discovery.notes]
        }
        // Validate the entire selection before writing any destination.
        let selectors = ["all", "targets", "folder"].filter { request[$0] != nil }
        guard selectors.count == 1 else {
            return invalid("Choose exactly one of all, targets, or folder.")
        }
        let selected: [SkillTarget]
        if request["all"] != nil {
            guard let flag = request["all"] as? NSNumber,
                  CFGetTypeID(flag) == CFBooleanGetTypeID(), flag.boolValue else {
                return invalid("all must be true.")
            }
            selected = discovery.targets
        } else if let raw = request["targets"] {
            guard let ids = raw as? [String], !ids.isEmpty, ids.count <= 100 else {
                return invalid("Provide 1 to 100 target IDs from skills list.")
            }
            let unknown = ids.filter { id in !discovery.targets.contains { $0.id == id } }
            guard unknown.isEmpty else { return invalid("Unknown target IDs. Run skills list again before installing.") }
            selected = discovery.targets.filter { ids.contains($0.id) }
        } else {
            guard let path = request["folder"] as? String, path.hasPrefix("/"),
                  !path.contains("\0"), path.utf8.count <= 4096 else {
                return invalid("folder must be an absolute skills directory path.")
            }
            selected = [SkillTarget(title: "Selected skills folder", root: URL(fileURLWithPath: path).standardizedFileURL)]
        }
        let results = selected.map { current.install($0) }
        let succeeded = results.allSatisfy { ["Installed", "Updated", "Already installed"].contains($0.state) }
        let entries = results.map { result -> [String: Any] in
            var entry = describe(result.target)
            entry["state"] = result.state.lowercased().replacingOccurrences(of: " ", with: "_")
            entry["detail"] = result.detail
            return entry
        }
        return ["status": succeeded ? "ok" : "partial_failure", "results": entries, "notes": discovery.notes,
                "message": "Start a new AI session to discover the skill. Results confirm files were installed, not that each host loaded them."]
    }
}
