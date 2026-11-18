import Foundation
import Ory
import OryTestDoubles
import Testing

/// Exercises the public configuration surface without `@testable`, so it fails when a
/// documented injection seam stops being usable by integrators.
@Suite("OryClientConfiguration")
struct OryClientConfigurationTests {

    private func makeClient(deviceKeyStore: InMemoryDeviceKeyStore) -> OryClient {
        OryClient(configuration: OryClientConfiguration(
            projectURL: URL(string: "https://example.com")!,
            sessionStorage: InMemorySessionStorage(),
            deviceKeyStore: deviceKeyStore
        ))
    }

    @Test("Client reads enrollment state from the injected device key store")
    func injectedDeviceKeyStore() async throws {
        // Given
        let key = OryStoredDeviceKey(
            clientKeyID: "server-key",
            localKeyID: "local-key",
            userVerification: .platform, identityID: "identity-1"
        )
        let client = makeClient(deviceKeyStore: InMemoryDeviceKeyStore(initial: key))

        // When / Then
        #expect(try await client.deviceEnrollment() == .enrolled(.platform))
    }

    @Test("forgetDevice clears the injected device key store")
    func forgetDeviceClearsInjectedStore() async throws {
        // Given
        let key = OryStoredDeviceKey(
            clientKeyID: "server-key",
            localKeyID: "local-key",
            userVerification: .none, identityID: "identity-1"
        )
        let store = InMemoryDeviceKeyStore(initial: key)
        let client = makeClient(deviceKeyStore: store)

        // When
        try await client.forgetDevice()

        // Then
        #expect(await store.stored == nil)
        #expect(await store.clearCallCount == 1)
    }

    @Test("PIN material is sealed with the Secure Enclave unless a test opts out")
    func pinSealingDefaultsToSecureEnclave() {
        let configuration = OryClientConfiguration(projectURL: URL(string: "https://example.com")!)

        #expect(configuration.pinSealingKeyProvider is OrySecureEnclavePINSealingKeyProvider)
    }

    @Test("usingInsecurePINSealingForTests shares one in-memory provider across configurations")
    func insecurePINSealingForTests() {
        // Given two clients of one test, as an E2E suite builds them
        let base = OryClientConfiguration(projectURL: URL(string: "https://example.com")!)

        // When
        let first = base.usingInsecurePINSealingForTests().pinSealingKeyProvider
        let second = base.usingInsecurePINSealingForTests().pinSealingKeyProvider

        // Then both seal with the same in-memory keys, the way they would share the Keychain
        let firstProvider = first as? InsecureEphemeralPINSealingKeyProvider
        #expect(firstProvider != nil)
        #expect(firstProvider === second as? InsecureEphemeralPINSealingKeyProvider)
    }
}
