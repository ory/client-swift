import Foundation
import OryClient
import OryClientTestDoubles
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
            userVerification: .platform
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
            userVerification: .none
        )
        let store = InMemoryDeviceKeyStore(initial: key)
        let client = makeClient(deviceKeyStore: store)

        // When
        try await client.forgetDevice()

        // Then
        #expect(await store.stored == nil)
        #expect(await store.clearCallCount == 1)
    }
}
