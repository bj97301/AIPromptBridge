import Foundation

final class DummyPasswordStore: PasswordStoring {
    var reads = 0
    var password = "fixture-password-not-a-real-credential"
    func isSaved() throws -> Bool { true }
    func save(_ password: String) throws { self.password = password }
    func read() throws -> String { reads += 1; return password }
    func delete() throws {}
}

@main
struct PasswordPolicyTests {
    static func main() throws {
        let suite = "AIPromptBridge-PolicyTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = OperationPolicy(defaults: defaults)
        let store = DummyPasswordStore()
        var accepted = true
        let requests = PasswordRequests(policy: policy, store: store, consent: { accepted })
        var written: [String] = []
        var targetAlive = true
        func check(_ condition: Bool, _ description: String) { if !condition { fatalError(description) } }
        func target(secure: Bool = true, expires: Date = Date().addingTimeInterval(60)) -> PreparedPasswordInput {
            PreparedPasswordInput(target: "Fixture secure field", secure: secure, expires: expires, validate: {
                targetAlive ? nil : ["status": "stale"]
            }, apply: { value in written.append(value); return ["status": "delivered", "secret_returned": false] })
        }
        let manual: [String: Any] = ["op": "fill", "source": "manual", "secret": "manual-fixture"]
        let saved: [String: Any] = ["op": "fill", "source": "saved"]
        func isStatus(_ value: [String: Any], _ expected: String) -> Bool { value["status"] as? String == expected }
        check(policy.allows(.buttons) && policy.allows(.askForPassword), "Buttons and ask-first defaults")
        check(!policy.allows(.manualInput) && !policy.allows(.savedPassword) && !policy.allows(.capture), "Input and capture require opt in")
        check(policy.denial(for: ["op": "scan"]) == nil, "Inspection stays available")
        check(isStatus(requests.start(manual, target: target()), "operation_not_allowed"), "Manual denied by default")
        check(isStatus(requests.start(saved, target: target()), "operation_not_allowed"), "Saved denied by default")
        check(store.reads == 0 && written.isEmpty, "Denied requests access no credential or field")
        policy.set(.manualInput, true); policy.set(.savedPassword, true)
        check(OperationPolicy(defaults: defaults).allows(.savedPassword), "Policy persists")
        check(isStatus(requests.start(["op": "fill", "source": "saved", "secret": "ambiguous"], target: target()), "invalid_request"), "Ambiguous source rejected")
        check(isStatus(requests.start(saved, target: target(secure: false)), "secure_field_required"), "Saved password cannot target a plain field")
        var pending = requests.start(saved, target: target())
        check(isStatus(pending, "approval_required"), "Saved use waits for native decision")
        let deniedID = pending["request_id"] as! String
        check(store.reads == 0 && written.isEmpty, "Waiting does not read Keychain or write field")
        check(isStatus(requests.result(deniedID), "approval_required"), "Polling cannot approve")
        check(isStatus(requests.start(manual, target: target()), "approval_busy"), "Only one pending password request")
        requests.decide(deniedID, allow: false)
        check(isStatus(requests.result(deniedID), "approval_denied"), "Denial reported")
        check(store.reads == 0 && written.isEmpty, "Denial never reads or types password")
        pending = requests.start(saved, target: target())
        let allowedID = pending["request_id"] as! String
        requests.decide(allowedID, allow: true)
        let delivered = requests.result(allowedID)
        check(isStatus(delivered, "delivered") && store.reads == 1 && written == [store.password], "Allowed saved input retrieves and delivers once")
        check(!String(describing: delivered).contains(store.password), "Saved value not in result")
        requests.decide(allowedID, allow: true)
        check(written.count == 1 && isStatus(requests.result(allowedID), "not_found"), "Approval and results are single use")
        pending = requests.start(manual.merging(["approved": true, "ask_before_password": false]) { _, new in new }, target: target())
        check(isStatus(pending, "approval_required"), "Payload cannot disable approval")
        let manualID = pending["request_id"] as! String
        requests.decide(manualID, allow: true)
        check(written.last == "manual-fixture" && store.reads == 1, "Manual input also requires approval and never reads Keychain")
        pending = requests.start(saved, target: target())
        let changedID = pending["request_id"] as! String
        policy.set(.askForPassword, false)
        requests.decide(changedID, allow: true)
        check(isStatus(requests.result(changedID), "operation_not_allowed") && store.reads == 1, "Policy changes invalidate prior approval")
        check(isStatus(requests.start(saved, target: target()), "delivered") && store.reads == 2, "Explicit ask-first opt out works")
        targetAlive = false
        check(isStatus(requests.start(saved, target: target()), "stale") && store.reads == 2, "Recheck target before reading saved password")
        targetAlive = true
        check(isStatus(requests.start(saved, target: target(expires: Date().addingTimeInterval(-1))), "expired") && store.reads == 2, "Expired input never reads password")
        policy.set(.askForPassword, true)
        pending = requests.start(saved, target: target())
        let cancelledID = pending["request_id"] as! String
        _ = requests.cancel(cancelledID)
        requests.decide(cancelledID, allow: true)
        check(isStatus(requests.result(cancelledID), "approval_denied") && store.reads == 2, "CLI cancellation prevents later delivery")
        pending = requests.start(saved, target: target())
        let revokedID = pending["request_id"] as! String
        accepted = false
        requests.decide(revokedID, allow: true)
        check(isStatus(requests.result(revokedID), "operation_not_allowed") && store.reads == 2, "Revoked consent prevents pending input")
        policy.set(.buttons, false)
        check(isStatus(policy.denial(for: ["op": "demo.press"])!, "operation_not_allowed"), "Demo and external buttons share policy")
        check(isStatus(policy.denial(for: ["op": "ocr"])!, "operation_not_allowed"), "OCR shares capture policy")
        print("PASS: defaults, persistence, operation gates, approval/denial, source validation, replay, revocation, cancellation, expiry, secure fields, target changes, and secret-free replies")
    }
}
