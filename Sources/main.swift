import AppKit
import ApplicationServices
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    let server = LocalServer()
    let accessibility = AccessibilityController()
    let capture = ScreenCapture()
    let consent = ConsentPolicy()
    var acknowledgmentCheckbox: NSButton?
    var enableButton: NSButton?
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var permissionLabel: NSTextField!
    var timer: Timer?
    var demo: NSAlert?
    var demoField: NSSecureTextField?
    var demoID: String?
    var demoExpires = Date.distantPast
    var demoResult: JSON = ["status": "ok", "result": "not_run"]
    var demoGeneration = UUID().uuidString

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            server.handle = { [weak self] request, reply in self?.handle(request, reply: reply) }
            try server.start()
        } catch {
            fputs("AIPromptBridge: \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
            return
        }
        buildMenu()
        buildWindow()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if !CommandLine.arguments.contains("--background") { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }

    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AIPromptBridge", action: #selector(showWindow), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AIPromptBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let top = NSMenuItem()
        top.submenu = appMenu
        main.addItem(top)
        let edit = NSMenuItem()
        edit.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "AIPromptBridge")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open AIPromptBridge", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Show test dialog", action: #selector(showDemoFromUI), keyEquivalent: "")
        menu.addItem(withTitle: "Pause CLI access", action: #selector(pauseAccess), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items { if item.action != #selector(NSApplication.terminate(_:)) { item.target = self } }
        statusItem.menu = menu
    }

    func buildWindow() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.center()
        }
        window.title = "AIPromptBridge"
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        permissionLabel = nil
        acknowledgmentCheckbox = nil
        enableButton = nil
        if !consent.isAccepted { buildRiskWindow(); return }
        window.setContentSize(NSSize(width: 680, height: 620))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 30)
        ])
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.isSelectable = true
            field.preferredMaxLayoutWidth = 616
            field.widthAnchor.constraint(equalToConstant: 616).isActive = true
            return field
        }
        stack.addArrangedSubview(label("Dialogs, from your terminal.", size: 27, weight: .semibold))
        stack.addArrangedSubview(label("Inspect app alerts, choose an exact button, or fill an exposed field. AIPromptBridge runs locally in your menu bar.", size: 14))
        permissionLabel = label("", size: 13, weight: .medium)
        stack.addArrangedSubview(permissionLabel)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.addArrangedSubview(NSButton(title: "Enable Accessibility…", target: self, action: #selector(openAccessibility)))
        buttons.addArrangedSubview(NSButton(title: "Enable Screen Recording…", target: self, action: #selector(openScreenRecording)))
        stack.addArrangedSubview(buttons)
        let commands = label("./aipromptbridge scan\n./aipromptbridge press ID --button 'Continue'\n./aipromptbridge fill ID --field field-1 --secret-prompt\n./aipromptbridge capture", size: 13)
        commands.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        commands.textColor = .secondaryLabelColor
        stack.addArrangedSubview(commands)
        stack.addArrangedSubview(label("Enable Accessibility to inspect and act on other apps. Screen Recording is optional and adds full-display capture with local text recognition.", size: 13))
        stack.addArrangedSubview(label("Some system prompts require direct interaction. Passwords are never read back. Captures happen only when requested.", size: 13))
        stack.addArrangedSubview(NSButton(title: "Show test dialog", target: self, action: #selector(showDemoFromUI)))
        stack.addArrangedSubview(NSButton(title: "Pause CLI access", target: self, action: #selector(pauseAccess)))
        refresh()
    }

    func buildRiskWindow() {
        window.setContentSize(NSSize(width: 740, height: 760))
        let content = window.contentView!
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.preferredMaxLayoutWidth = 684
            field.widthAnchor.constraint(equalToConstant: 684).isActive = true
            return field
        }
        stack.addArrangedSubview(label("Before you enable computer control", size: 25, weight: .semibold))
        stack.addArrangedSubview(label("Local agents and scripts can press buttons and enter text in other apps. Mistakes can expose information, approve access, or cause loss. Review the risk notice and license before continuing.", size: 14))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 668, height: 440))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.textContainer?.widthTracksTextView = true
        text.autoresizingMask = .width
        text.isVerticallyResizable = true
        text.minSize = NSSize(width: 0, height: 440)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.string = consent.available ? consent.notice : "The bundled license or risk notice is missing or invalid. Rebuild the app from the complete repository. CLI controls remain disabled."
        scroll.documentView = text
        scroll.widthAnchor.constraint(equalToConstant: 684).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(scroll)
        let checkbox = NSButton(checkboxWithTitle: "I have read the notices and accept the risks and liability limitations.", target: self, action: #selector(acknowledgmentChanged))
        checkbox.state = .off
        checkbox.isEnabled = consent.available
        acknowledgmentCheckbox = checkbox
        stack.addArrangedSubview(checkbox)
        stack.addArrangedSubview(label("Provided AS IS, without warranties. Applicable law may limit liability exclusions. Your acknowledgment is stored only on this Mac.", size: 12))
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.addArrangedSubview(NSButton(title: "Read license…", target: self, action: #selector(readLicense)))
        let enable = NSButton(title: "Enable AIPromptBridge", target: self, action: #selector(acceptRisks))
        enable.isEnabled = false
        enableButton = enable
        buttons.addArrangedSubview(enable)
        buttons.addArrangedSubview(NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:))))
        stack.addArrangedSubview(buttons)
    }

    @objc func acknowledgmentChanged() {
        enableButton?.isEnabled = consent.available && acknowledgmentCheckbox?.state == .on
    }

    @objc func acceptRisks() {
        guard acknowledgmentCheckbox?.state == .on, consent.recordAcknowledgment() else { return }
        buildWindow()
        showWindow()
    }

    @objc func pauseAccess() {
        consent.revoke()
        accessibility.invalidateTickets()
        demoID = nil
        buildWindow()
        showWindow()
    }

    @objc func readLicense() {
        let alert = NSAlert()
        alert.messageText = "Apache License 2.0"
        alert.informativeText = "Review the complete license, including Sections 7 and 8 on warranty, risk, and liability."
        alert.addButton(withTitle: "Done")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 420))
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        text.isEditable = false
        text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.autoresizingMask = .width
        text.string = consent.license.isEmpty ? "Bundled license unavailable." : consent.license
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.beginSheetModal(for: window)
    }

    func refresh() {
        permissionLabel?.stringValue = "Accessibility: \(AXIsProcessTrusted() ? "enabled" : "needs setup")     Screen Recording: \(CGPreflightScreenCaptureAccess() ? "enabled" : "optional, not enabled")"
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    @objc func openAccessibility() {
        guard consent.isAccepted else { showWindow(); return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func openScreenRecording() {
        guard consent.isAccepted else { showWindow(); return }
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func showDemoFromUI() { _ = showDemo(password: true) }

    func showDemo(password: Bool) -> JSON {
        guard consent.isAccepted else { showWindow(); return failure("acknowledgment_required", "Review and acknowledge the notices in the app first.") }
        if demo != nil { return failure("already_open", "Close the current test dialog first.") }
        let alert = NSAlert()
        alert.messageText = "AIPromptBridge test dialog"
        alert.informativeText = password ? "Use a dummy access key to test hidden input, then choose Continue or Cancel. This does not sign in or change settings." : "Choose Continue or Cancel through the CLI. This does not change settings."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        if password {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
            field.placeholderString = "Dummy access key"
            field.setAccessibilityLabel("Dummy access key")
            alert.accessoryView = field
            demoField = field
        }
        demo = alert
        demoGeneration = UUID().uuidString
        demoID = nil
        demoResult = ["status": "ok", "result": "open"]
        showWindow()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            self.demoResult = ["status": "ok", "result": response == .alertFirstButtonReturn ? "continued" : "cancelled",
                               "field_was_nonempty": !(self.demoField?.stringValue.isEmpty ?? true), "secret_returned": false]
            self.demoField?.stringValue = ""
            self.demoField = nil
            self.demo = nil
            self.demoID = nil
        }
        return ["status": "ok", "message": "Test dialog is open."]
    }

    func demoScan() -> JSON {
        guard let alert = demo else { return ["status": "ok", "dialogs": []] }
        let id = UUID().uuidString.lowercased()
        demoID = id
        demoExpires = Date().addingTimeInterval(60)
        var fields: [JSON] = []
        if demoField != nil { fields.append(["id": "field-1", "label": "Dummy access key", "secure": true, "enabled": true, "writable": true]) }
        return ["status": "ok", "dialogs": [["id": id, "source": "self_test", "title": alert.messageText,
                  "text": [alert.informativeText], "fingerprint": demoGeneration, "expires_at": demoExpires.timeIntervalSince1970,
                  "buttons": alert.buttons.enumerated().map { ["id": "button-\($0.offset + 1)", "label": $0.element.title, "enabled": $0.element.isEnabled] }, "fields": fields]],
                "note": "Self-test uses actual AppKit controls inside AIPromptBridge. It does not test cross-app Accessibility." ]
    }

    func demoAction(_ request: JSON, reply: @escaping (JSON) -> Void) {
        guard let id = request["id"] as? String, id == demoID, demoExpires > Date(), let alert = demo else {
            reply(failure("stale", "Test dialog ID is expired, used, or unknown. Run demo scan again.")); return
        }
        demoID = nil
        if request["op"] as? String == "demo.fill" {
            guard request["field"] as? String == "field-1", let field = demoField,
                  let value = request["secret"] as? String, !value.isEmpty, value.utf8.count <= 16_384 else {
                reply(failure("invalid_request", "Provide a dummy key and field-1.")); return
            }
            field.stringValue = value
            reply(["status": "delivered", "secret_returned": false]); return
        }
        guard let label = request["button"] as? String, let button = alert.buttons.first(where: { $0.title == label }) else {
            reply(failure("not_found", "Button label does not match.")); return
        }
        button.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in reply(self?.demoResult ?? [:]) }
    }

    func handle(_ request: JSON, reply: @escaping (JSON) -> Void) {
        let op = request["op"] as? String ?? ""
        if !["status", "open", "risks"].contains(op), !consent.isAccepted {
            reply(failure("acknowledgment_required", "Open AIPromptBridge, review the risk notice and license, and explicitly acknowledge them before using CLI controls.", extra: ["acknowledgment": consent.status]))
            return
        }
        switch op {
        case "status": reply(["status": "ok", "version": "0.1.0", "pid": getpid(), "bundle_id": bridgeID,
                              "accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess(),
                              "acknowledgment": consent.status,
                              "transport": "unix_socket", "socket": socketPath, "password_input": "write_only_supported_ax_fields"])
        case "open": showWindow(); reply(["status": "ok"])
        case "risks": reply(["status": "ok", "notice": consent.notice, "license": consent.license, "acknowledgment": consent.status])
        case "apps": reply(accessibility.apps())
        case "scan": reply(accessibility.scan(request))
        case "press", "fill": accessibility.act(request, reply: reply)
        case "capture": capture.capture(request, reply: reply)
        case "ocr": capture.ocr(request, reply: reply)
        case "demo.show": reply(showDemo(password: request["password"] as? Bool ?? true))
        case "demo.scan": reply(demoScan())
        case "demo.press", "demo.fill": demoAction(request, reply: reply)
        case "demo.result": reply(demoResult)
        default: reply(failure("invalid_request", "Unknown operation."))
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
