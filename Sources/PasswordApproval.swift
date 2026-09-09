import AppKit

final class PasswordApprovalController: NSWindowController, NSWindowDelegate {
    let requestID: String
    let decided: (Bool) -> Void
    private var finished = false

    init(request: PasswordRequests.Pending, decided: @escaping (Bool) -> Void) {
        requestID = request.id
        self.decided = decided
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Approve password use"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        let title = NSTextField(labelWithString: "Allow this password input?")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let source = request.saved ? "your saved Keychain password" : "the value supplied through the CLI"
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 496, height: 190))
        text.isEditable = false; text.isSelectable = true
        text.font = .systemFont(ofSize: 13)
        text.textContainer?.widthTracksTextView = true
        text.autoresizingMask = .width
        text.isVerticallyResizable = true
        text.string = "Local software wants to enter \(source) into:\n\n\(request.target.target)\n\nAllow once fills this field only. It does not submit the dialog. This request expires at \(request.target.expires.formatted(date: .omitted, time: .standard))."
        scroll.documentView = text
        scroll.widthAnchor.constraint(equalToConstant: 512).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 190).isActive = true
        stack.addArrangedSubview(scroll)
        let buttons = NSStackView()
        buttons.spacing = 12
        let deny = NSButton(title: "Deny", target: self, action: #selector(denyInput))
            .withHelp("Reject this request without entering a value. Your saved password and allowed actions stay as they are.")
        deny.keyEquivalent = "\r"
        buttons.addArrangedSubview(deny)
        buttons.addArrangedSubview(NSButton(title: "Allow once", target: self, action: #selector(allowInput))
            .withHelp("Approve input into the displayed field once, before this request expires. This does not submit the target dialog."))
        stack.addArrangedSubview(buttons)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func allowInput() { finish(true) }
    @objc private func denyInput() { finish(false) }
    private func finish(_ allow: Bool) {
        guard !finished else { return }
        finished = true
        decided(allow)
        close()
    }
    func dismiss() { finished = true; close() }
    func windowWillClose(_ notification: Notification) { if !finished { finished = true; decided(false) } }
}
