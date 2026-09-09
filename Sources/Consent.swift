import Foundation
import CryptoKit

/// A local acknowledgment gate, not identity verification or protection against
/// another process that already controls the same macOS user account.
final class ConsentPolicy {
    static let receiptKey = "riskAcknowledgment"
    let notice: String
    let license: String
    let version: String
    let digest: String
    let available: Bool
    private let defaults: UserDefaults

    init(noticeURL: URL? = Bundle.main.url(forResource: "RISK_NOTICE", withExtension: "md"),
         licenseURL: URL? = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
         defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let noticeData = noticeURL.flatMap { try? Data(contentsOf: $0) }
        let licenseData = licenseURL.flatMap { try? Data(contentsOf: $0) }
        notice = noticeData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        license = licenseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        version = notice.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("Notice version: ") })?
            .replacingOccurrences(of: "Notice version: ", with: "") ?? ""
        available = !notice.isEmpty && !license.isEmpty && !version.isEmpty
        if let noticeData = noticeData, let licenseData = licenseData, available {
            // Separate digests avoid ambiguity from concatenating arbitrary documents.
            let n = SHA256.hash(data: noticeData).map { String(format: "%02x", $0) }.joined()
            let l = SHA256.hash(data: licenseData).map { String(format: "%02x", $0) }.joined()
            digest = SHA256.hash(data: Data(("AIPromptBridge risk acknowledgment v1\n" + n + "\n" + l).utf8))
                .map { String(format: "%02x", $0) }.joined()
        } else { digest = "" }
    }

    var isAccepted: Bool {
        guard available, let receipt = defaults.dictionary(forKey: Self.receiptKey),
              receipt["digest"] as? String == digest,
              receipt["notice_version"] as? String == version,
              receipt["method"] as? String == "app_checkbox",
              let time = receipt["accepted_at"] as? Double,
              time.isFinite, time > 0, time <= Date().timeIntervalSince1970 + 5 else { return false }
        return true
    }

    @discardableResult
    func recordAcknowledgment() -> Bool {
        guard available else { return false }
        defaults.set(["digest": digest, "notice_version": version,
                      "method": "app_checkbox", "accepted_at": Date().timeIntervalSince1970], forKey: Self.receiptKey)
        return isAccepted
    }

    func revoke() { defaults.removeObject(forKey: Self.receiptKey) }

    var status: [String: Any] {
        ["accepted": isAccepted, "documents_available": available, "notice_version": version, "documents_sha256": digest]
    }
}
