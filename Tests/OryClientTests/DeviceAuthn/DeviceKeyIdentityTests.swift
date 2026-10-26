import Foundation
import Testing
import OryClientTestDoubles
@testable import OryClient

@Suite("Device key owner")
struct DeviceKeyIdentityTests {

    private let sealingKeys = InsecureEphemeralPINSealingKeyProvider()

    private func makeClient(
        frontend: FakeFrontendRepository,
        keyStore: InMemoryDeviceKeyStore
    ) -> OryClient {
        OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st_aal1"),
            frontend: frontend,
            deviceAuthn: frontend,
            deviceKeyStore: keyStore,
            deviceAuthenticator: FakeDeviceKeyAuthenticator(
                attestation: .success(OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation))
            ),
            biometricAuthenticator: FakeBiometricAuthenticator(),
            biometricSignInReason: OryClientConfiguration.defaultBiometricSignInReason,
            biometricEnrollReason: OryClientConfiguration.defaultBiometricEnrollReason,
            pinSealingKeyProvider: sealingKeys
        )
    }

    private func key(owner: String) -> OryStoredDeviceKey {
        OryStoredDeviceKey(clientKeyID: "srv-key", localKeyID: "old-key", userVerification: .none, identityID: owner)
    }

    private func session(identityID: String?, assuranceLevel: OryAuthenticatorAssuranceLevel = .aal1) -> OrySession {
        Sample.session(assuranceLevel: assuranceLevel, identity: identityID.map { Sample.identity(id: $0) })
    }

    // MARK: - Enrollment

    @Test("Enrolling for another account than the stored key's owner fails without changing anything")
    func enrollForAnotherAccount() async throws {
        // Given a key enrolled by another identity
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake(identityID: "identity-1")),
            submitEnrollment: .success([Fixture.attestedClientKeyID])
        )
        let keyStore = InMemoryDeviceKeyStore(initial: key(owner: "identity-other"))
        let client = makeClient(frontend: frontend, keyStore: keyStore)

        // When
        let error = await #expect(throws: OryClientError.self) {
            try await client.enrollDevice(name: "My iPhone")
        }

        // Then the other account's key stays and nothing was registered
        #expect(error?.isDeviceAuthenticationEnrolledForAnotherAccount == true)
        #expect(await keyStore.stored == key(owner: "identity-other"))
        #expect(await frontend.submittedDeviceName == nil)
    }

    // MARK: - Enrollment state

    @Test(
        "deviceEnrollment(for:) reports a key of another account",
        arguments: [
            (owner: "identity-1", sessionIdentity: "identity-1" as String?, expected: OryDeviceEnrollmentState.enrolled(.none)),
            (owner: "identity-other", sessionIdentity: "identity-1", expected: .enrolledForAnotherAccount),
            (owner: "identity-other", sessionIdentity: nil, expected: .enrolled(.none)),
        ]
    )
    func enrollmentForSession(owner: String, sessionIdentity: String?, expected: OryDeviceEnrollmentState) async throws {
        // Given
        let keyStore = InMemoryDeviceKeyStore(initial: key(owner: owner))
        let client = makeClient(frontend: FakeFrontendRepository(), keyStore: keyStore)

        // When
        let state = try await client.deviceEnrollment(for: session(identityID: sessionIdentity))

        // Then
        #expect(state == expected)
    }

    @Test("deviceEnrollment(for:) without a key reports notEnrolled")
    func enrollmentForSessionWithoutKey() async throws {
        let client = makeClient(frontend: FakeFrontendRepository(), keyStore: InMemoryDeviceKeyStore())

        #expect(try await client.deviceEnrollment(for: session(identityID: "identity-1")) == .notEnrolled)
    }

    @Test("A protocol conformance without its own implementation reports deviceEnrollment()")
    func defaultEnrollmentForSession() async throws {
        let stub = OryClientStub(deviceEnrollmentResult: .success(.enrolled(.pin)))

        #expect(try await stub.deviceEnrollment(for: session(identityID: "identity-1")) == .enrolled(.pin))
    }

    // MARK: - Step-up

    @Test("Step-up with another account's key fails before signing")
    func stepUpWithAnotherAccountsKey() async throws {
        // Given a signed-in identity and a key enrolled by another one
        let frontend = FakeFrontendRepository(
            currentSession: .success(session(identityID: "identity-1")),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake())
        )
        let client = makeClient(frontend: frontend, keyStore: InMemoryDeviceKeyStore(initial: key(owner: "identity-other")))

        // When
        let error = await #expect(throws: OryClientError.self) {
            _ = try await client.authenticateWithDevice()
        }

        // Then
        #expect(error?.isDeviceAuthenticationEnrolledForAnotherAccount == true)
        #expect(await frontend.submittedClientKeyID == nil)
    }
}

private extension OryClientError {
    var isDeviceAuthenticationEnrolledForAnotherAccount: Bool {
        if case .deviceAuthenticationEnrolledForAnotherAccount = self { true } else { false }
    }
}
