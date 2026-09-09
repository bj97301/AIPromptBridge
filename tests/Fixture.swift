import AppKit

// A separate process for end-to-end AX testing, never a real credential prompt.
final class Fixture: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "AIPromptBridge AX fixture"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AIPromptBridge external test"
        alert.informativeText = "This separate app accepts only a dummy test value. Continue records whether it matched; Cancel dismisses the test."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "Dummy access key"
        field.setAccessibilityLabel("Dummy access key")
        alert.accessoryView = field
        alert.beginSheetModal(for: window) { response in
            let result: [String: Any] = ["result": response == .alertFirstButtonReturn ? "continued" : "cancelled", "dummy_matched": field.stringValue == "fixture-dummy-input", "secret_returned": false]
            if let index = CommandLine.arguments.firstIndex(of: "--result"), index + 1 < CommandLine.arguments.count,
               let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            }
            field.stringValue = ""
            // Let AXPress return before this fixture exits its event loop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
    }
}

let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
