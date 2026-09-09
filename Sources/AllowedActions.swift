import AppKit

final class AllowedActionsController: NSWindowController {
    let policy: OperationPolicy
    let store: PasswordStoring
    let changed: () -> Void
    var controls: [BridgeCapability: NSButton] = [:]
    let savedLabel = NSTextField(wrappingLabelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")

    init(policy: OperationPolicy, store: PasswordStoring, changed: @escaping () -> Void) {
        self.policy = policy; self.store = store; self.changed = changed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Allowed actions"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        let title = NSTextField(labelWithString: "Choose what AI tools may do")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(title)
        for (capability, title) in [
            (BridgeCapability.buttons, "Allow prompt buttons, such as OK, Continue, and Cancel"),
            (.manualInput, "Allow manual password or text input from the CLI"),
            (.savedPassword, "Allow the CLI to use the saved password"),
            (.askForPassword, "Ask me before each password use"),
            (.capture, "Allow screenshots and OCR")
        ] {
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(capability.rawValue)
            controls[capability] = checkbox
            stack.addArrangedSubview(checkbox)
        }
        let detail = NSTextField(wrappingLabelWithString: "Ask first applies to both manual and saved input. Each approval names the target app and field and expires with the dialog ID. A saved password can only go into a secure field. Local software on your account can request these actions.")
        detail.preferredMaxLayoutWidth = 624
        detail.widthAnchor.constraint(equalToConstant: 624).isActive = true
        detail.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(detail)
        stack.addArrangedSubview(savedLabel)
        let buttons = NSStackView()
        buttons.spacing = 10
        buttons.addArrangedSubview(NSButton(title: "Save or replace password…", target: self, action: #selector(savePassword)))
        buttons.addArrangedSubview(NSButton(title: "Delete saved password", target: self, action: #selector(deletePassword)))
        buttons.addArrangedSubview(NSButton(title: "Done", target: self, action: #selector(done)))
        stack.addArrangedSubview(buttons)
        message.font = .systemFont(ofSize: 12)
        message.preferredMaxLayoutWidth = 624
        message.widthAnchor.constraint(equalToConstant: 624).isActive = true
        stack.addArrangedSubview(message)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        for (capability, checkbox) in controls { checkbox.state = policy.allows(capability) ? .on : .off }
        do { savedLabel.stringValue = try store.isSaved() ? "Password: saved in macOS Keychain" : "Password: none saved" }
        catch { savedLabel.stringValue = "Password: Keychain status unavailable" }
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue, let capability = BridgeCapability(rawValue: name) else { return }
        let enabled = sender.state == .on
        if capability == .savedPassword && enabled {
            do {
                if try !store.isSaved() { refresh(); savePassword(); return }
            } catch { message.stringValue = error.localizedDescription; refresh(); return }
        }
        policy.set(capability, enabled)
        changed(); refresh()
        if capability == .manualInput && enabled {
            // Enabling input always offers secure storage, with a manual-only escape.
            savePassword()
        }
    }

    @objc private func savePassword() {
        let alert = NSAlert()
        alert.messageText = "Save a password securely?"
        alert.informativeText = "AIPromptBridge stores it in this Mac's Keychain and never returns it to the CLI. Save enables saved-password input. You can keep using manual input without storing a password."
        alert.addButton(withTitle: "Save & allow CLI use")
        alert.addButton(withTitle: "Keep current settings")
        // NSAlert measures its accessory's frame before laying out the sheet.
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 64))
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 38, width: 340, height: 26))
        password.placeholderString = "Password"
        password.setAccessibilityLabel("Password to store in Keychain")
        let confirmation = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        confirmation.placeholderString = "Confirm password"
        confirmation.setAccessibilityLabel("Confirm password to store")
        for field in [password, confirmation] {
            fields.addSubview(field)
        }
        alert.accessoryView = fields
        alert.beginSheetModal(for: window!) { [weak self] response in
            defer { password.stringValue = ""; confirmation.stringValue = "" }
            guard let self, response == .alertFirstButtonReturn else { return }
            guard !password.stringValue.isEmpty, password.stringValue == confirmation.stringValue,
                  password.stringValue.utf8.count <= 16_384 else {
                self.message.stringValue = "Passwords must match and contain 1 to 16384 UTF-8 bytes. Nothing was saved."
                return
            }
            do {
                try self.store.save(password.stringValue)
                self.policy.set(.savedPassword, true)
                self.changed()
                self.message.stringValue = "Saved in Keychain. The CLI can request input, but cannot read the password."
            } catch { self.message.stringValue = error.localizedDescription }
            self.refresh()
        }
    }

    @objc private func deletePassword() {
        do {
            try store.delete()
            policy.set(.savedPassword, false)
            changed(); refresh()
            message.stringValue = "Saved password deleted. Manual input settings are unchanged."
        } catch { message.stringValue = error.localizedDescription }
    }

    @objc private func done() { close() }
}
