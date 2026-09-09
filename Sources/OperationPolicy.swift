import Foundation

enum BridgeCapability: String, CaseIterable {
    case buttons, manualInput = "manual_input", savedPassword = "saved_password"
    case capture, askForPassword = "ask_before_password"
}

final class OperationPolicy {
    private let defaults: UserDefaults
    private let key = "allowedOperations"
    private(set) var generation = UUID()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func allows(_ capability: BridgeCapability) -> Bool {
        let stored = defaults.dictionary(forKey: key)?[capability.rawValue]
        if let value = stored as? Bool { return value }
        return capability == .buttons || capability == .askForPassword
    }

    func set(_ capability: BridgeCapability, _ allowed: Bool) {
        var values = defaults.dictionary(forKey: key) ?? [:]
        values[capability.rawValue] = allowed
        defaults.set(values, forKey: key)
        invalidate()
    }

    func invalidate() { generation = UUID() }

    var status: [String: Bool] {
        Dictionary(uniqueKeysWithValues: BridgeCapability.allCases.map { ($0.rawValue, allows($0)) })
    }

    func denial(for request: [String: Any]) -> [String: Any]? {
        let op = request["op"] as? String ?? ""
        var capability: BridgeCapability?
        switch op {
        case "press", "demo.press": capability = .buttons
        case "fill", "demo.fill":
            let source = request["source"] as? String ?? "manual"
            guard source == "saved" || source == "manual",
                  !(source == "saved" && request["secret"] != nil) else {
                return ["status": "invalid_request", "message": "Choose either saved input or manual input."]
            }
            capability = source == "saved" ? .savedPassword : .manualInput
        case "capture", "ocr": capability = .capture
        default: break
        }
        if let capability, !allows(capability) {
            return ["status": "operation_not_allowed", "capability": capability.rawValue,
                    "message": "This operation is disabled. Change Allowed actions in AIPromptBridge to enable it."]
        }
        return nil
    }
}

struct BridgeInputError: LocalizedError {
    let response: [String: Any]
    init(_ status: String, _ message: String) { response = ["status": status, "message": message] }
    var errorDescription: String? { response["message"] as? String }
}

/// A consumed dialog ticket. The setter must revalidate the live target at delivery.
struct PreparedPasswordInput {
    let target: String
    let secure: Bool
    let expires: Date
    let validate: () -> [String: Any]?
    let apply: (String) -> [String: Any]
}
