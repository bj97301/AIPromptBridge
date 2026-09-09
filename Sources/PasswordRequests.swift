import Foundation
import Security

/// Approval is an app callback, never a CLI operation. Only one request is pending.
final class PasswordRequests {
    struct Pending {
        let id: String
        let target: PreparedPasswordInput
        let saved: Bool
        let generation: UUID
        var manual: String?
    }
    let policy: OperationPolicy
    let store: PasswordStoring
    let consent: () -> Bool
    private(set) var pending: Pending?
    private var results: [String: (Date, [String: Any])] = [:]

    init(policy: OperationPolicy, store: PasswordStoring, consent: @escaping () -> Bool) {
        self.policy = policy; self.store = store; self.consent = consent
    }

    private func failure(_ status: String, _ message: String) -> [String: Any] { ["status": status, "message": message] }

    func start(_ request: [String: Any], target: PreparedPasswordInput) -> [String: Any] {
        expire()
        guard consent() else { return failure("acknowledgment_required", "Review the notices in the app first.") }
        if let denied = policy.denial(for: request) { return denied }
        guard pending == nil else { return failure("approval_busy", "Another password request is waiting for your approval.") }
        let saved = request["source"] as? String == "saved"
        guard !saved || target.secure else { return failure("secure_field_required", "Saved passwords may only be entered into a field identified as secure.") }
        let manual = request["secret"] as? String
        guard saved || (manual?.isEmpty == false && (manual?.utf8.count ?? 0) <= 16_384) else {
            return failure("invalid_request", "Provide a password through hidden input or stdin.")
        }
        let item = Pending(id: UUID().uuidString.lowercased(), target: target, saved: saved,
                           generation: policy.generation, manual: manual)
        if !policy.allows(.askForPassword) { return deliver(item) }
        pending = item
        return waiting(item)
    }

    private func waiting(_ item: Pending) -> [String: Any] {
        ["status": "approval_required", "request_id": item.id, "expires_at": item.target.expires.timeIntervalSince1970,
         "message": "Approve this password use in AIPromptBridge. The CLI cannot approve it."]
    }

    private func deliver(_ item: Pending) -> [String: Any] {
        guard consent(), policy.generation == item.generation,
              policy.allows(item.saved ? .savedPassword : .manualInput) else {
            return failure("operation_not_allowed", "Access settings changed; request cancelled. Scan again.")
        }
        guard item.target.expires > Date() else { return failure("expired", "Password request expired. Scan again.") }
        if let invalid = item.target.validate() { return invalid }
        do {
            var secret = item.saved ? try store.read() : (item.manual ?? "")
            defer { secret.removeAll(keepingCapacity: false) }
            // The target revalidates its fingerprint, expiry, and field immediately before writing.
            return item.target.apply(secret)
        } catch let error as PasswordStoreError {
            return failure(error.code == errSecItemNotFound ? "password_not_saved" : "keychain_error", error.localizedDescription)
        } catch { return failure("keychain_error", "The password could not be retrieved from Keychain.") }
    }

    func decide(_ id: String, allow: Bool) {
        guard let item = pending, item.id == id else { return }
        pending = nil
        results[id] = (Date().addingTimeInterval(60), allow ? deliver(item) : failure("approval_denied", "Password use was denied in AIPromptBridge."))
    }

    func cancel(_ id: String) -> [String: Any] {
        guard pending?.id == id else { return failure("not_found", "No matching pending password request.") }
        decide(id, allow: false)
        return ["status": "ok"]
    }

    func invalidate() {
        if let item = pending {
            pending = nil
            results[item.id] = (Date().addingTimeInterval(60), failure("operation_not_allowed", "Access changed; password request cancelled."))
        }
    }

    func expire() {
        results = results.filter { $0.value.0 > Date() }
        if let item = pending, item.target.expires <= Date() {
            pending = nil
            results[item.id] = (Date().addingTimeInterval(60), failure("expired", "Password request expired. Scan again."))
        }
    }

    func result(_ id: String) -> [String: Any] {
        expire()
        if let item = pending, item.id == id { return waiting(item) }
        if let completed = results.removeValue(forKey: id) { return completed.1 }
        return failure("not_found", "Password request is unknown, expired, or its result was already collected.")
    }
}
