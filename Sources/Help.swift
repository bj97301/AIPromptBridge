import AppKit

extension NSView {
    @discardableResult
    func withHelp(_ text: String) -> Self {
        toolTip = text
        setAccessibilityHelp(text)
        return self
    }
}

enum AppHelp {
    static let open = "Show AIPromptBridge's setup, permissions, and CLI examples."
    static let allowed = "Choose which buttons, field input, saved passwords, and screenshots local tools may use."
    static let skills = "Install the AIPromptBridge skill for your AI apps or export a portable ZIP. This does not grant computer control."
    static let bug = "Open the public GitHub issue tracker. Remove passwords and private information from your report."
    static let demo = "Open a harmless dialog to test exact button presses and hidden dummy input. No sign-in or settings change occurs."
    static let pause = "Block new CLI control requests and cancel pending password requests. Resuming requires acknowledging the notices again."
    static let quit = "Quit AIPromptBridge. A later CLI command can start it again; use Pause CLI access to keep control blocked."
    static let done = "Close this window. Changes you already made remain in effect."

    static func apply(to menu: NSMenu) {
        let entries = [
            "About AIPromptBridge": open, "Open AIPromptBridge": open,
            "Allowed actions…": allowed, "Install AI skill…": skills,
            "Report a bug…": bug, "Show test dialog": demo,
            "Pause CLI access": pause, "Quit": quit, "Quit AIPromptBridge": quit,
            "Copy": "Copy the selected text to the clipboard.",
            "Paste": "Paste clipboard text into the focused editable field.",
            "Select All": "Select all text in the focused text area."
        ]
        for item in menu.items {
            if let text = entries[item.title] { item.toolTip = text }
            if let submenu = item.submenu { apply(to: submenu) }
        }
    }
}
