import AppKit
import ApplicationServices
import CryptoKit

struct AXControl {
    let id: String
    let element: AXUIElement
    let data: JSON
}

struct DialogState {
    let root: AXUIElement
    let process: NSRunningApplication
    let fingerprint: String
    let data: JSON
    let buttons: [AXControl]
    let fields: [AXControl]
}

struct DialogTicket {
    let state: DialogState
    let expires: Date
}

final class AccessibilityController {
    private var tickets: [String: DialogTicket] = [:]

    func invalidateTickets() { tickets.removeAll() }

    func apps() -> JSON {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map { app -> JSON in
            ["pid": app.processIdentifier, "bundle_id": app.bundleIdentifier ?? "", "name": app.localizedName ?? "", "active": app.isActive]
        }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return ["status": "ok", "apps": apps]
    }

    func scan(_ request: JSON) -> JSON {
        guard AXIsProcessTrusted() else {
            return failure("permission_required", "Enable AIPromptBridge in System Settings > Privacy & Security > Accessibility.", extra: ["permission": "accessibility", "dialogs": []])
        }
        tickets = tickets.filter { $0.value.expires > Date() }
        let deadline = min(request["deadline"] as? Double ?? Date().timeIntervalSince1970 + 10, Date().timeIntervalSince1970 + 10)
        let appFilter = request["app"] as? String
        let pidFilter = request["pid"] as? Int32
        var processes = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != getpid()
                && (appFilter == nil || $0.bundleIdentifier == appFilter)
                && (pidFilter == nil || $0.processIdentifier == pidFilter)
        }
        processes.sort { ($0.isActive ? 0 : 1, $0.processIdentifier) < ($1.isActive ? 0 : 1, $1.processIdentifier) }
        var dialogs: [JSON] = []
        var coverage: [JSON] = []
        for process in processes {
            if Date().timeIntervalSince1970 >= deadline {
                coverage.append(["pid": process.processIdentifier, "status": "time_budget_exhausted"])
                break
            }
            let app = AXUIElementCreateApplication(process.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.20)
            var rawWindows: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &rawWindows)
            guard result == .success else {
                coverage.append(["pid": process.processIdentifier, "bundle_id": process.bundleIdentifier ?? "", "status": "unavailable", "ax_error": result.rawValue])
                continue
            }
            var windows = rawWindows as? [AXUIElement] ?? []
            if let focused = axElement(app, kAXFocusedWindowAttribute), !windows.contains(where: { CFEqual($0, focused) }) { windows.append(focused) }
            var roots: [AXUIElement] = []
            var budget = 1000
            var visited = Set<CFHashCode>()
            for window in windows {
                findDialogs(window, depth: 0, budget: &budget, visited: &visited, deadline: deadline, roots: &roots)
            }
            for root in roots {
                if Date().timeIntervalSince1970 >= deadline { break }
                guard let state = describe(root, process: process, deadline: deadline) else { continue }
                let id = UUID().uuidString.lowercased()
                let expiration = Date().addingTimeInterval(60)
                tickets[id] = DialogTicket(state: state, expires: expiration)
                var item = state.data
                item["id"] = id
                item["expires_at"] = expiration.timeIntervalSince1970
                dialogs.append(item)
            }
            coverage.append(["pid": process.processIdentifier, "bundle_id": process.bundleIdentifier ?? "", "status": budget <= 0 || Date().timeIntervalSince1970 >= deadline ? "partial" : "inspected", "windows": windows.count])
        }
        // Bound retained AX references when watch mode runs for a long time.
        if tickets.count > 1000 {
            let newest = tickets.sorted { $0.value.expires > $1.value.expires }.prefix(1000)
            tickets = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        return ["status": "ok", "dialogs": dialogs, "coverage": coverage,
                "complete": false, "note": "Lists exposed dialogs and sheets. Custom or protected prompts may be missing. Use capture for visual inspection."]
    }

    private func findDialogs(_ node: AXUIElement, depth: Int, budget: inout Int, visited: inout Set<CFHashCode>, deadline: Double, roots: inout [AXUIElement]) {
        guard depth <= 9, budget > 0, Date().timeIntervalSince1970 < deadline else { return }
        guard visited.insert(CFHash(node)).inserted else { return }
        budget -= 1
        let role = axString(node, kAXRoleAttribute)
        let subrole = axString(node, kAXSubroleAttribute)
        if role == kAXSheetRole || subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole || axBool(node, kAXModalAttribute) {
            if !roots.contains(where: { CFEqual($0, node) }) { roots.append(node) }
            return
        }
        // Standard windows may contain attached sheets or custom AXDialog groups.
        var children = axElements(node, kAXChildrenAttribute)
        for sheet in axElements(node, "AXSheets") where !children.contains(where: { CFEqual($0, sheet) }) { children.append(sheet) }
        for child in children { findDialogs(child, depth: depth + 1, budget: &budget, visited: &visited, deadline: deadline, roots: &roots) }
    }

    private func describe(_ root: AXUIElement, process: NSRunningApplication, deadline: Double) -> DialogState? {
        var nodes: [AXUIElement] = []
        var budget = 500
        var visited = Set<CFHashCode>()
        func walk(_ node: AXUIElement, depth: Int) {
            guard depth <= 15, budget > 0, Date().timeIntervalSince1970 < deadline, visited.insert(CFHash(node)).inserted else { return }
            budget -= 1
            nodes.append(node)
            for child in axElements(node, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        guard budget > 0, Date().timeIntervalSince1970 < deadline else { return nil }
        let defaultButton = axElement(root, kAXDefaultButtonAttribute)
        let cancelButton = axElement(root, kAXCancelButtonAttribute)
        var texts: [String] = []
        var buttons: [AXControl] = []
        var fields: [AXControl] = []
        for node in nodes {
            if Date().timeIntervalSince1970 >= deadline { return nil }
            let role = axString(node, kAXRoleAttribute)
            let subrole = axString(node, kAXSubroleAttribute)
            if role == kAXStaticTextRole {
                let text = axString(node, kAXValueAttribute)
                if !text.isEmpty, !texts.contains(text) { texts.append(String(text.prefix(4000))) }
            }
            if role == kAXButtonRole {
                let id = "button-\(buttons.count + 1)"
                let title = axString(node, kAXTitleAttribute)
                let label = title.isEmpty ? axString(node, kAXDescriptionAttribute) : title
                let data: JSON = ["id": id, "label": label, "enabled": axBool(node, kAXEnabledAttribute),
                                  "press_supported": axActions(node).contains(kAXPressAction),
                                  "default": defaultButton.map { CFEqual($0, node) } ?? false,
                                  "cancel": cancelButton.map { CFEqual($0, node) } ?? false]
                buttons.append(AXControl(id: id, element: node, data: data))
            }
            if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole {
                let id = "field-\(fields.count + 1)"
                var label = axString(node, kAXTitleAttribute)
                if label.isEmpty { label = axString(node, kAXDescriptionAttribute) }
                if label.isEmpty { label = axString(node, kAXPlaceholderValueAttribute) }
                let data: JSON = ["id": id, "label": label, "secure": subrole == kAXSecureTextFieldSubrole,
                                  "enabled": axBool(node, kAXEnabledAttribute), "writable": axSettable(node)]
                // Never request AXValue for editable fields, including password fields.
                fields.append(AXControl(id: id, element: node, data: data))
            }
        }
        let stable: JSON = ["title": axString(root, kAXTitleAttribute), "text": texts,
                            "role": axString(root, kAXRoleAttribute), "subrole": axString(root, kAXSubroleAttribute),
                            "buttons": buttons.map { $0.data }, "fields": fields.map { $0.data }]
        guard let encoded = try? JSONSerialization.data(withJSONObject: stable, options: [.sortedKeys]) else { return nil }
        let fingerprint = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        var data = stable
        data["pid"] = process.processIdentifier
        data["app"] = process.bundleIdentifier ?? ""
        data["app_name"] = process.localizedName ?? ""
        data["frame"] = axFrame(root)
        data["source"] = "accessibility"
        data["fingerprint"] = fingerprint
        return DialogState(root: root, process: process, fingerprint: fingerprint, data: data, buttons: buttons, fields: fields)
    }

    private func live(_ state: DialogState, deadline: Double) -> Bool {
        guard !state.process.isTerminated else { return false }
        let app = AXUIElementCreateApplication(state.process.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var roots: [AXUIElement] = []
        var visited = Set<CFHashCode>()
        var budget = 1000
        var windows = axElements(app, kAXWindowsAttribute)
        if let focused = axElement(app, kAXFocusedWindowAttribute), !windows.contains(where: { CFEqual($0, focused) }) { windows.append(focused) }
        for window in windows { findDialogs(window, depth: 0, budget: &budget, visited: &visited, deadline: deadline, roots: &roots) }
        return roots.contains { CFEqual($0, state.root) }
    }

    func act(_ request: JSON, reply: @escaping (JSON) -> Void) {
        guard AXIsProcessTrusted() else { reply(failure("permission_required", "Enable AIPromptBridge Accessibility access first.")); return }
        guard let id = request["id"] as? String, let ticket = tickets.removeValue(forKey: id), ticket.expires > Date() else {
            reply(failure("stale", "Dialog ID expired, was already used, or is unknown. Scan again.")); return
        }
        let deadline = request["deadline"] as? Double ?? 0
        guard live(ticket.state, deadline: deadline),
              let current = describe(ticket.state.root, process: ticket.state.process, deadline: deadline),
              current.fingerprint == ticket.state.fingerprint else {
            reply(failure("stale", "The dialog closed or changed. Scan again before acting.")); return
        }
        guard Date().timeIntervalSince1970 < deadline else { reply(failure("expired", "Request expired.")); return }
        if request["op"] as? String == "fill" {
            guard let fieldID = request["field"] as? String,
                  let field = current.fields.first(where: { $0.id == fieldID }),
                  let secret = request["secret"] as? String, !secret.isEmpty, secret.utf8.count <= 16_384 else {
                reply(failure("invalid_request", "Choose an exact field ID and provide up to 16384 bytes through hidden input or stdin.")); return
            }
            guard field.data["enabled"] as? Bool == true, field.data["writable"] as? Bool == true else {
                reply(failure("user_interaction_required", "The field does not expose a writable Accessibility value. Enter it directly in the target app.")); return
            }
            let error = AXUIElementSetAttributeValue(field.element, kAXValueAttribute as CFString, secret as CFString)
            if error != .success { reply(axError(error)); return }
            reply(["status": "delivered", "operation": "fill", "message": "The app accepted the field update. Its contents were not read back. Scan again to choose a button.", "secret_returned": false])
            return
        }
        guard let label = request["button"] as? String, !label.isEmpty else {
            reply(failure("invalid_request", "Specify the exact visible button label.")); return
        }
        let matching = current.buttons.filter { $0.data["label"] as? String == label }
        guard matching.count == 1, let button = matching.first else {
            reply(failure("ambiguous", "The exact button label is missing or appears more than once. Scan again.")); return
        }
        guard button.data["enabled"] as? Bool == true, button.data["press_supported"] as? Bool == true else {
            reply(failure("user_interaction_required", "The button is disabled or does not expose AXPress.")); return
        }
        let error = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        if error != .success { reply(axError(error)); return }
        // A successful AXPress is delivery, not proof that an operation completed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            let checkDeadline = Date().timeIntervalSince1970 + 2
            let stillPresent = live(current, deadline: checkDeadline)
            let updated = stillPresent ? describe(current.root, process: current.process, deadline: checkDeadline) : nil
            let changed = updated.map { $0.fingerprint != current.fingerprint } ?? false
            reply(["status": "delivered", "operation": "press", "button": label,
                   "observed": !stillPresent ? "dialog_no_longer_found" : changed ? "dialog_changed" : "dialog_still_present",
                   "message": "AXPress was accepted. Verify the target app's resulting state before assuming success."])
        }
    }
}
