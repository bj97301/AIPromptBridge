import Foundation

@main
struct KeychainTests {
    static func main() throws {
        let store = KeychainPasswordStore(service: "io.github.bj97301.aipromptbridge.test." + UUID().uuidString)
        defer { try? store.delete() }
        guard try !store.isSaved() else { fatalError("Unique test item unexpectedly exists") }
        let dummy = "temporary-dummy-" + UUID().uuidString
        try store.save(dummy)
        guard try store.isSaved(), try store.read() == dummy else { fatalError("Keychain round trip failed") }
        try store.save(dummy + "updated")
        guard try store.read() == dummy + "updated" else { fatalError("Keychain replacement failed") }
        try store.delete()
        guard try !store.isSaved() else { fatalError("Test item was not deleted") }
        print("PASS: real macOS Keychain save, read, replacement, and deletion using an isolated dummy item")
    }
}
