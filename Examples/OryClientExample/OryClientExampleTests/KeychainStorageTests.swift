import Foundation
import OryClient
import Security
import Testing

/// Exercises the real Keychain-backed storage that ships as `OryClient`'s default.
///
/// These live in the example app's test target because they need one: a test bundle without a
/// host application has no Keychain entitlement, and every `SecItem` call fails with `-34018`
/// (`errSecMissingEntitlement`) — on the Simulator *and* on the macOS host that runs
/// `swift test`. The package's own suites therefore substitute in-memory stores, which leaves
/// the code that actually protects the session token and the device key untested. This is the
/// cheapest place where it runs for real.
///
/// Every test uses a service of its own, so nothing leaks between tests or between runs.
@Suite("Keychain storage")
struct KeychainStorageTests {

    private func uniqueService() -> String { "com.ory.client.tests.\(UUID().uuidString)" }

    // MARK: - Session token

    @Test("stores, reads back, and clears a session token")
    func sessionTokenRoundTrip() async throws {
        let storage = OryKeychainSessionStorage(service: uniqueService())

        #expect(try await storage.sessionToken() == nil)

        try await storage.store(sessionToken: "ory_st_first")
        #expect(try await storage.sessionToken() == "ory_st_first")

        // Storing again must update in place rather than insert a duplicate the reads would
        // then pick between arbitrarily.
        try await storage.store(sessionToken: "ory_st_second")
        #expect(try await storage.sessionToken() == "ory_st_second")

        try await storage.clear()
        #expect(try await storage.sessionToken() == nil)
    }

    @Test("clearing an empty store is not an error")
    func clearingEmptyStorage() async throws {
        try await OryKeychainSessionStorage(service: uniqueService()).clear()
    }

    @Test("the session token is device-bound and readable in the background")
    func sessionTokenAccessibility() async throws {
        // The guarantee the docs make: readable after first unlock (so background work keeps
        // working after a reboot) but never restored onto another device from a backup.
        let service = uniqueService()
        let storage = OryKeychainSessionStorage(service: service)
        try await storage.store(sessionToken: "ory_st_attrs")
        defer { Task { try? await storage.clear() } }

        let accessible = try #require(accessibility(service: service, account: "session_token"))
        #expect(accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    }

    // MARK: - Device key

    @Test("stores, reads back, and clears a device key")
    func deviceKeyRoundTrip() async throws {
        let store = OryKeychainDeviceKeyStore(service: uniqueService())
        let key = OryStoredDeviceKey(clientKeyID: "srv-1", localKeyID: "apple-1", userVerification: .pin, identityID: "identity-1")

        #expect(try await store.enrolledKey() == nil)

        try await store.store(key)
        #expect(try await store.enrolledKey() == key)

        let replacement = OryStoredDeviceKey(clientKeyID: "srv-2", localKeyID: "apple-2", userVerification: .platform, identityID: "identity-1")
        try await store.store(replacement)
        #expect(try await store.enrolledKey() == replacement)

        try await store.clear()
        #expect(try await store.enrolledKey() == nil)
    }

    @Test("the device key never leaves this device and is unavailable while locked")
    func deviceKeyAccessibility() async throws {
        let service = uniqueService()
        let store = OryKeychainDeviceKeyStore(service: service)
        try await store.store(OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .pin, identityID: "identity-1"))
        defer { Task { try? await store.clear() } }

        let accessible = try #require(accessibility(service: service, account: "device_key"))
        #expect(accessible == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String))
    }

    @Test("a record written by a newer build reads as not enrolled, not as a failure")
    func unreadableRecordReadsAsAbsent() async throws {
        // Writing a future schema version directly, as an SDK upgrade would leave behind after
        // a downgrade. The app must be able to enroll again rather than be stuck on an error.
        let service = uniqueService()
        let store = OryKeychainDeviceKeyStore(service: service)
        defer { Task { try? await store.clear() } }

        let future = Data(#"""
        {"schemaVersion":99,"clientKeyID":"srv","localKeyID":"apple","userVerification":"pin"}
        """#.utf8)
        try write(future, service: service, account: "device_key")

        #expect(try await store.enrolledKey() == nil)
    }

    @Test("the session and device stores do not collide on a shared service")
    func storesDoNotCollide() async throws {
        // Both default to the same service and are told apart only by their account, so a
        // collision here would have one silently overwrite the other.
        let service = uniqueService()
        let session = OryKeychainSessionStorage(service: service)
        let device = OryKeychainDeviceKeyStore(service: service)
        defer { Task { try? await session.clear(); try? await device.clear() } }

        try await session.store(sessionToken: "ory_st_shared")
        try await device.store(OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .none, identityID: "identity-1"))

        #expect(try await session.sessionToken() == "ory_st_shared")
        #expect(try await device.enrolledKey()?.clientKeyID == "srv")

        // Clearing one leaves the other intact — signing out must not un-enroll the device.
        try await session.clear()
        #expect(try await device.enrolledKey() != nil)
    }

    // MARK: - Keychain helpers

    private func accessibility(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any]
        else {
            return nil
        }
        return attributes[kSecAttrAccessible as String] as? String
    }

    private func write(_ data: Data, service: String, account: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        #expect(status == errSecSuccess, "seeding the Keychain failed with \(status)")
    }
}
