import AppKit
import UniformTypeIdentifiers

final class SkillSetupController: NSWindowController {
    let installer: SkillInstaller
    let resources: URL
    var targets: [SkillTarget] = []
    var checkboxes: [NSButton] = []
    var resultView = NSTextView()

    init(resources: URL, app: URL) {
        self.resources = resources
        installer = SkillInstaller(payload: resources.appendingPathComponent("aipromptbridge-skill"), app: app)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Install AI skill"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat = 13) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.isSelectable = true
        field.preferredMaxLayoutWidth = 712
        field.widthAnchor.constraint(equalToConstant: 712).isActive = true
        return field
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24)
        ])
        stack.addArrangedSubview(label("Teach your AI apps to use AIPromptBridge", size: 23))
        stack.addArrangedSubview(label("Install instructions and a local CLI in the selected skill folders. Existing custom skills are preserved. This does not accept the risks, grant Mac permissions, or change agent approval settings."))

        let discovery = installer.discover()
        targets = discovery.targets
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 10
        list.translatesAutoresizingMaskIntoConstraints = false
        for target in targets {
            let checkbox = NSButton(checkboxWithTitle: target.title, target: nil, action: nil)
            checkbox.state = .on
            checkboxes.append(checkbox)
            list.addArrangedSubview(checkbox)
            let path = label(target.destination.path, size: 11)
            path.textColor = .secondaryLabelColor
            list.addArrangedSubview(path)
        }
        let targetScroll = NSScrollView()
        targetScroll.hasVerticalScroller = true
        targetScroll.borderType = .bezelBorder
        targetScroll.documentView = list
        targetScroll.widthAnchor.constraint(equalToConstant: 712).isActive = true
        targetScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        list.widthAnchor.constraint(equalToConstant: 712).isActive = true
        stack.addArrangedSubview(targetScroll)
        stack.addArrangedSubview(label("T3 Code uses its local provider skills. Current ChatGPT desktop versions can discover local skills. Claude web/Cowork needs a ZIP upload in Customize > Skills. Web and remote sessions need a separate connection to control this Mac; a skill alone cannot provide it."))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.addArrangedSubview(NSButton(title: "Install selected", target: self, action: #selector(installSelected)))
        buttons.addArrangedSubview(NSButton(title: "Choose skills folder…", target: self, action: #selector(chooseFolder)))
        buttons.addArrangedSubview(NSButton(title: "Export skill ZIP…", target: self, action: #selector(exportSkill)))
        buttons.addArrangedSubview(NSButton(title: "Done", target: self, action: #selector(closeSetup)))
        stack.addArrangedSubview(buttons)

        let results = NSScrollView()
        results.hasVerticalScroller = true
        results.borderType = .bezelBorder
        resultView = NSTextView(frame: NSRect(x: 0, y: 0, width: 690, height: 145))
        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.font = .systemFont(ofSize: 12)
        resultView.textContainerInset = NSSize(width: 10, height: 10)
        resultView.textContainer?.widthTracksTextView = true
        resultView.autoresizingMask = .width
        resultView.isVerticallyResizable = true
        resultView.string = (["Ready. After installing, start a new AI session and ask it to use the aipromptbridge skill. Installation confirms files were written; discovery depends on the app version and its settings."] + discovery.notes).joined(separator: "\n\n")
        results.documentView = resultView
        results.widthAnchor.constraint(equalToConstant: 712).isActive = true
        results.heightAnchor.constraint(equalToConstant: 145).isActive = true
        stack.addArrangedSubview(results)
    }

    private func show(_ results: [SkillInstallResult]) {
        resultView.string = results.map { "\($0.state): \($0.target.title)\n\($0.detail)" }.joined(separator: "\n\n")
        resultView.string += "\n\nStart a new AI session to discover the skill. Installation does not verify that each AI app has loaded it."
        resultView.scrollToBeginningOfDocument(nil)
    }

    @objc private func installSelected() {
        let selected = zip(targets, checkboxes).filter { $0.1.state == .on }.map { $0.0 }
        guard !selected.isEmpty else { resultView.string = "Select at least one destination."; return }
        show(selected.map { installer.install($0) })
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Install here"
        panel.message = "Choose another app's skills folder. AIPromptBridge will add an aipromptbridge folder inside it."
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.show([self.installer.install(SkillTarget(title: "Selected skills folder", root: url))])
        }
    }

    @objc private func exportSkill() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "aipromptbridge-skill.zip"
        panel.message = "Export the portable skill without this Mac's app path. Upload to Claude's skills settings, or extract SKILL.md for tools that accept instructions. ChatGPT web/mobile requires its supported plugin setup for a reusable skill."
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let bytes = try Data(contentsOf: self.resources.appendingPathComponent("aipromptbridge-skill.zip"))
                try bytes.write(to: url, options: .atomic)
                self.resultView.string = "Exported: \(url.path)\n\nThis is an export, not an account installation. A cloud or remote session cannot control this Mac through the skill alone."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { self.resultView.string = "Export failed: \(error.localizedDescription)" }
        }
    }

    @objc private func closeSetup() { close() }
}
