#!/usr/bin/env python3
"""Test local receipt validity without accepting the installed app's notices."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SWIFT = r'''
import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let suite = "io.github.bj97301.aipromptbridge.tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let notice = folder.appendingPathComponent("notice.md")
let license = folder.appendingPathComponent("LICENSE")
try "Notice version: test.1\nTest risk notice.".write(to: notice, atomically: true, encoding: .utf8)
try "Test license.".write(to: license, atomically: true, encoding: .utf8)
func policy() -> ConsentPolicy { ConsentPolicy(noticeURL: notice, licenseURL: license, defaults: defaults) }
let initial = policy()
check(initial.available, "Documents should be available")
check(!initial.isAccepted, "Fresh setup must block operations")
check(initial.recordAcknowledgment(), "Explicit acknowledgment should be recorded")
check(policy().isAccepted, "Receipt should survive constructing a new policy")
try "Test license changed.".write(to: license, atomically: true, encoding: .utf8)
check(!policy().isAccepted, "A license change must invalidate the receipt")
check(policy().recordAcknowledgment(), "Changed documents require new acknowledgment")
try "Notice version: test.2\nTest risk notice changed.".write(to: notice, atomically: true, encoding: .utf8)
check(!policy().isAccepted, "A notice change must invalidate the receipt")
check(policy().recordAcknowledgment(), "New notice can be acknowledged explicitly")
policy().revoke()
check(!policy().isAccepted, "Pause must revoke the receipt")
check(policy().recordAcknowledgment(), "Resume requires a new receipt")
var receipt = defaults.dictionary(forKey: ConsentPolicy.receiptKey)!
receipt["accepted_at"] = Date().timeIntervalSince1970 + 86400
defaults.set(receipt, forKey: ConsentPolicy.receiptKey)
check(!policy().isAccepted, "Future-dated receipt must fail")
receipt["accepted_at"] = Date().timeIntervalSince1970
receipt["method"] = "unrecognized"
defaults.set(receipt, forKey: ConsentPolicy.receiptKey)
check(!policy().isAccepted, "Unknown acknowledgment method must fail")
try FileManager.default.removeItem(at: license)
let missing = policy()
check(!missing.available && !missing.isAccepted && !missing.recordAcknowledgment(), "Missing resources must fail closed")
print("PASS: fresh setup, explicit receipt, persistence, document changes, revocation, invalid receipts, and missing resources")
'''

with tempfile.TemporaryDirectory(prefix="aipromptbridge-consent-") as directory:
    folder = Path(directory)
    (folder / "main.swift").write_text(SWIFT)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(ROOT / "Sources" / "Consent.swift"), str(folder / "main.swift"), "-o", str(folder / "consent-tests")], check=True)
    subprocess.run([str(folder / "consent-tests")], check=True)
