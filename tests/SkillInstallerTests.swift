import Foundation

@main
struct SkillInstallerTests {
    static func main() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("AIPromptBridge-Skills-" + UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let home = scratch.appendingPathComponent("home with spaces")
        let payload = scratch.appendingPathComponent("payload")
        let app = home.appendingPathComponent("Apps/AIPromptBridge.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        func write(_ url: URL, _ text: String) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        func check(_ value: Bool, _ message: String) {
            guard value else { fatalError(message) }
        }
        for (path, contents) in ["SKILL.md": "original instructions", "scripts/aipromptbridge": "#!/usr/bin/env python3\n", "references/LICENSE": "license", "references/RISK_NOTICE.md": "risk notice"] {
            try write(payload.appendingPathComponent(path), contents)
        }
        let installer = SkillInstaller(home: home, environment: [:], payload: payload, app: app)
        let base = installer.discover()
        check(base.targets.count == 2 && base.notes.isEmpty, "Shared agents and Claude defaults")
        let shared = base.targets[0]
        let result = installer.install(shared)
        check(result.state == "Installed", "Fresh installation: \(result.detail)")
        let location = shared.destination.appendingPathComponent("scripts/app-location.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: location)) as! [String: String]
        check(json["appPath"] == app.path, "Installed CLI remembers the app location")
        check(installer.install(shared).state == "Already installed", "Reinstall is idempotent")
        try write(shared.destination.appendingPathComponent("SKILL.md"), "user edited this")
        check(installer.install(shared).state == "Skipped", "Preserve edits")
        check(try String(contentsOf: shared.destination.appendingPathComponent("SKILL.md"), encoding: .utf8) == "user edited this", "Edit survived")
        let unknown = SkillTarget(title: "Existing skill", root: home.appendingPathComponent("existing/skills"))
        try write(unknown.destination.appendingPathComponent("SKILL.md"), "user skill")
        check(installer.install(unknown).state == "Skipped", "Preserve an unowned skill")
        let updating = base.targets[1]
        check(installer.install(updating).state == "Installed", "Install for update test")
        try write(payload.appendingPathComponent("SKILL.md"), "updated instructions")
        check(installer.install(updating).state == "Updated", "Update unedited managed skill")
        let backupRoot = home.appendingPathComponent("Library/Application Support/AIPromptBridge/Skill Backups")
        let backups = try fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        check(backups.count == 1, "Update makes one backup outside discovery directories")
        check(try String(contentsOf: backups[0].appendingPathComponent("SKILL.md"), encoding: .utf8) == "original instructions", "Backup retains old content")
        try write(updating.destination.appendingPathComponent("custom.txt"), "keep me")
        check(installer.install(updating).state == "Skipped", "Preserve additional user files")
        let links = SkillTarget(title: "Linked skill", root: home.appendingPathComponent("links/skills"))
        try fm.createDirectory(at: links.root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: links.destination, withDestinationURL: unknown.destination)
        check(installer.install(links).state == "Failed", "Do not replace a skill symlink")
        let broken = SkillTarget(title: "Dangling link", root: home.appendingPathComponent("broken/skills"))
        try fm.createDirectory(at: broken.root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: broken.destination, withDestinationURL: home.appendingPathComponent("missing"))
        check(installer.install(broken).state == "Failed", "Do not replace a dangling symlink")
        let special = SkillTarget(title: "Linked file", root: home.appendingPathComponent("special/skills"))
        check(installer.install(special).state == "Installed", "Install linked-file fixture")
        try fm.createSymbolicLink(at: special.destination.appendingPathComponent("custom-link"), withDestinationURL: location)
        check(installer.install(special).state == "Failed", "Do not follow a nested link")
        let badRoot = home.appendingPathComponent("not-a-directory")
        try write(badRoot, "a file")
        check(installer.install(SkillTarget(title: "Bad folder", root: badRoot)).state == "Failed", "Report individual destination failure")
        let incomplete = SkillInstaller(home: home, environment: [:], payload: scratch.appendingPathComponent("absent"), app: app)
        check(incomplete.install(base.targets[0]).state == "Failed", "Missing bundle fails without writes")

        // Only provider home paths are consumed. Unknown and disabled drivers are ignored.
        let settings = home.appendingPathComponent(".t3/userdata/settings.json")
        try write(settings, #"{"providerInstances":{"custom":{"driver":"claudeAgent","config":{"homePath":"~/.claude-alt"}},"normal":{"driver":"claudeAgent"},"off":{"driver":"claudeAgent","enabled":false,"config":{"homePath":"~/.off"}},"remote":{"driver":"claudeAgent","config":{"homePath":"/some-other-account"}},"relative":{"driver":"claudeAgent","config":{"homePath":"relative"}},"codex":{"driver":"codex"}}}"#)
        let detected = installer.discover()
        check(detected.targets.count == 3, "T3 custom profile and deduplicated default")
        check(detected.targets.contains { $0.root.path == home.appendingPathComponent(".claude-alt/skills").path }, "T3 custom profile resolved")
        check(detected.notes.count == 2, "Out-of-account and relative paths require explicit selection")
        let overridden = SkillInstaller(home: home, environment: ["CLAUDE_CONFIG_DIR": "~/.env-claude"], payload: payload, app: app)
        check(overridden.discover().targets.contains { $0.root.path == home.appendingPathComponent(".env-claude/skills").path }, "Claude environment override")
        try write(settings, "invalid JSON")
        check(installer.discover().notes.count == 1, "Corrupt T3 settings are reported")
        check(installer.discover().targets.count == 2, "Corrupt T3 settings do not block default installs")
        print("PASS: skill destinations, app location, idempotency, managed update and backup, edited/unowned files, symlinks, partial failure, missing resources, and T3 configuration")

        let commandHome = scratch.appendingPathComponent("command home")
        let commands = SkillCommands(installer: SkillInstaller(home: commandHome, environment: [:], payload: payload, app: app))
        let listed = commands.handle(["op": "skills.list"])
        let targets = listed["targets"] as! [[String: Any]]
        check(targets.map { $0["id"] as! String } == ["shared", "claude"], "Stable default target IDs")
        check(!fm.fileExists(atPath: commandHome.path), "Listing is read-only")
        for selection: [String: Any] in [[:], ["all": true, "targets": ["shared"]], ["all": false], ["all": 1],
                                         ["targets": []], ["targets": ["shared", "unknown"]], ["folder": "relative"]] {
            var request = selection
            request["op"] = "skills.install"
            check(commands.handle(request)["status"] as? String == "invalid_request", "Invalid selection refused: \(selection)")
            check(!fm.fileExists(atPath: commandHome.path), "Entire selection validated before writes")
        }
        let installed = commands.handle(["op": "skills.install", "targets": ["shared", "shared"]])
        check(installed["status"] as? String == "ok", "Selected install succeeds")
        check((installed["results"] as! [[String: Any]]).count == 1, "Duplicate IDs install once")
        check(!fm.fileExists(atPath: commandHome.appendingPathComponent(".claude").path), "Targeted install leaves other destinations alone")
        let repeated = commands.handle(["op": "skills.install", "targets": ["shared"]])
        check((repeated["results"] as! [[String: Any]])[0]["state"] as? String == "already_installed", "Command reinstall is idempotent")
        let sharedInstructions = commandHome.appendingPathComponent(".agents/skills/aipromptbridge/SKILL.md")
        try write(sharedInstructions, "keep customized instructions")
        let partial = commands.handle(["op": "skills.install", "all": true])
        check(partial["status"] as? String == "partial_failure", "Skipped destination is not complete success")
        check((partial["results"] as! [[String: Any]]).map { $0["state"] as! String } == ["skipped", "installed"], "All destinations report their individual results")
        check(try String(contentsOf: sharedInstructions, encoding: .utf8) == "keep customized instructions", "Command preserves customized skill")
        let selectedFolder = scratch.appendingPathComponent("chosen skills")
        check(commands.handle(["op": "skills.install", "folder": selectedFolder.path])["status"] as? String == "ok", "Explicit folder install")
        check(fm.fileExists(atPath: selectedFolder.appendingPathComponent("aipromptbridge/SKILL.md").path), "Custom folder gets only the named skill")
        let configured = commands.handle(["op": "skills.list", "claude_config_dir": "~/.custom-claude"])
        check((configured["targets"] as! [[String: Any]])[1]["skills_folder"] as? String == commandHome.appendingPathComponent(".custom-claude/skills").path, "CLI Claude environment reaches discovery")
        let refused = commands.handle(["op": "skills.list", "claude_config_dir": "/another-account"])
        check((refused["notes"] as! [String]).count == 1 && (refused["targets"] as! [[String: Any]]).count == 1, "Automatic homes remain scoped to this account")
        check(commands.handle(["op": "skills.approve"])["status"] as? String == "invalid_request", "Unknown setup operations are refused")
        check(commands.handle(["op": "skills.export"])["status"] as? String == "export_failed", "Missing ZIP is explicit")
        let archive = payload.deletingLastPathComponent().appendingPathComponent("aipromptbridge-skill.zip")
        let archiveData = Data("opaque archive fixture".utf8)
        try archiveData.write(to: archive)
        let exported = commands.handle(["op": "skills.export"])
        check(exported["status"] as? String == "ok" && Data(base64Encoded: exported["archive_base64"] as! String) == archiveData, "Export returns bundled bytes")
        print("PASS: setup commands list without writes, validate selections, install exact targets, preserve edits, report partial results, honor configured homes, and export bundled data")
    }
}
