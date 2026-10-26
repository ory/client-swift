import CryptoKit
import Foundation
import Testing
import OryClientTestDoubles
@testable import OryClient

@Suite("OryClient device authn")
struct OryClientDeviceAuthnTests {

    /// One sealing-key provider per test, shared between the vault that prepares stored
    /// PIN material and the client under test — the same way one device shares its
    /// Secure Enclave.
    private let sealingKeys = InsecureEphemeralPINSealingKeyProvider()
    private var vault: DevicePINVault { DevicePINVault(sealingKeyProvider: sealingKeys) }

    /// The server's rendering of a rejected `pin_proof`: HTTP 400 with the
    /// `ErrorValidationDeviceAuthnVerifierWrong` message (4000044). A wrong PIN, an
    /// unknown key, and a locked key all render exactly like this (anti-enumeration).
    private static let serverRejectsProof = OryClientError.server(
        status: 400,
        id: nil,
        messages: [OryUIMessage(id: 4_000_044, text: "The provided DeviceAuthn signature is invalid.", kind: .error)]
    )

    private func makeClient(
        token: String? = "ory_st_aal1",
        frontend: FakeFrontendRepository = FakeFrontendRepository(),
        keyStore: InMemoryDeviceKeyStore = InMemoryDeviceKeyStore(),
        authenticator: any OryDeviceKeyAuthenticator = FakeDeviceKeyAuthenticator(),
        biometric: any OryBiometricAuthenticator = FakeBiometricAuthenticator(),
        signInReason: String = OryClientConfiguration.defaultBiometricSignInReason,
        enrollReason: String = OryClientConfiguration.defaultBiometricEnrollReason
    ) -> (OryClient, InMemorySessionStorage, InMemoryDeviceKeyStore) {
        let storage = token.map { InMemorySessionStorage(initialToken: $0) } ?? InMemorySessionStorage()
        let client = OryClient(
            storage: storage,
            frontend: frontend,
            deviceAuthn: frontend,
            deviceKeyStore: keyStore,
            deviceAuthenticator: authenticator,
            biometricAuthenticator: biometric,
            biometricSignInReason: signInReason,
            biometricEnrollReason: enrollReason,
            pinSealingKeyProvider: sealingKeys
        )
        return (client, storage, keyStore)
    }

    // MARK: - Availability

    @Test("isDeviceAuthenticationAvailable reflects the authenticator")
    func availabilityReflectsAuthenticator() {
        let (available, _, _) = makeClient(authenticator: FakeDeviceKeyAuthenticator(isAvailable: true))
        let (unavailable, _, _) = makeClient(authenticator: FakeDeviceKeyAuthenticator(isAvailable: false))

        #expect(available.isDeviceAuthenticationAvailable)
        #expect(!unavailable.isDeviceAuthenticationAvailable)
    }

    // MARK: - Enrollment

    @Test("Enrollment keeps its own fingerprint when multiple devices were added", arguments: [OryDeviceUserVerification.none, .pin, .platform])
    func enrollmentCorrelatesAttestedKey(verification: OryDeviceUserVerification) async throws {
        // Given a response containing the existing key and two newly enrolled keys.
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake()),
            submitEnrollment: .success(["existing", "concurrent", Fixture.attestedClientKeyID]),
            concurrentEnrollmentKeyIDs: ["existing", "concurrent"]
        )
        let (client, _, keyStore) = makeClient(frontend: frontend)

        // When this enrollment returns after another device has also enrolled.
        switch verification {
        case .none: try await client.enrollDevice(name: "Same device name")
        case .pin: try await client.enrollDevice(name: "Same device name", protection: .pin("1234"))
        case .platform: try await client.enrollDevice(name: "Same device name", protection: .biometrics)
        }

        // Then correlation uses the attested key, regardless of ordering or display name.
        let stored = try #require(await keyStore.stored)
        #expect(stored.clientKeyID == Fixture.attestedClientKeyID)
        #expect(stored.localKeyID == "apple-key")
        #expect(stored.userVerification == verification)
        if verification == .pin {
            #expect(try vault.unlock(#require(stored.pinSecret), pinString: "1234") == Data(repeating: 9, count: 32))
        }
    }

    @Test("Unparseable attestation fails before enrollment is submitted", arguments: [OryDeviceUserVerification.none, .pin, .platform])
    func malformedAttestationDoesNotEnroll(verification: OryDeviceUserVerification) async throws {
        // Given an authenticator that cannot supply a usable App Attest certificate.
        let frontend = FakeFrontendRepository()
        let authenticator = FakeDeviceKeyAuthenticator(attestation: .success(
            OryDeviceKeyAttestation(keyID: "local", attestation: Data([0xa0]))
        ))
        let previous = OryStoredDeviceKey(clientKeyID: "previous", localKeyID: "previous-local", userVerification: .none, identityID: "identity-1")
        let keyStore = InMemoryDeviceKeyStore(initial: previous)
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore, authenticator: authenticator)

        // When enrollment cannot derive a key identity locally.
        do {
            switch verification {
            case .none: try await client.enrollDevice(name: "iPhone")
            case .pin: try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))
            case .platform: try await client.enrollDevice(name: "iPhone", protection: .biometrics)
            }
            Issue.record("Malformed attestation must stop enrollment")
        } catch let error as OryClientError {
            guard case .deviceAuthenticationFailed = error else {
                Issue.record("Expected deviceAuthenticationFailed, got \(error)")
                return
            }
        }

        // Then no key was committed remotely, and existing local state is preserved.
        #expect(await frontend.submitCallCount == 0)
        #expect(await keyStore.stored == previous)
    }

    @Test("Enrollment rejects a response containing only another device's key", arguments: [OryDeviceUserVerification.none, .pin, .platform])
    func enrollmentRejectsUnrelatedKey(verification: OryDeviceUserVerification) async throws {
        // Given a real attested key, but the response contains only an unrelated key.
        let frontend = FakeFrontendRepository(
            submitEnrollment: .success(["another-device"]),
            pinClientKeyID: "another-device"
        )
        let previous = OryStoredDeviceKey(clientKeyID: "previous", localKeyID: "previous-local", userVerification: .none, identityID: "identity-1")
        let keyStore = InMemoryDeviceKeyStore(initial: previous)
        let authenticator = FakeDeviceKeyAuthenticator(attestation: .success(
            OryDeviceKeyAttestation(keyID: "apple-local-handle", attestation: Fixture.deviceAttestation)
        ))
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore, authenticator: authenticator)

        // When the server response cannot confirm this device's own fingerprint.
        do {
            switch verification {
            case .none: try await client.enrollDevice(name: "iPhone")
            case .pin: try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))
            case .platform: try await client.enrollDevice(name: "iPhone", protection: .biometrics)
            }
            Issue.record("Enrollment must reject a response without the attested key")
        } catch let error as OryClientError {
            guard case .unexpectedResponse = error else {
                Issue.record("Expected unexpectedResponse, got \(error)")
                return
            }
        }

        // Then an unrelated key must never replace the existing local enrollment.
        #expect(await keyStore.stored == previous)
    }

    @Test("enrollDevice correlates the server key id with the local key and stores the pair")
    func enrollStoresCorrelatedKey() async throws {
        // Given the identity has no keys yet and enrollment yields one new server id
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake()),
            submitEnrollment: .success([Fixture.attestedClientKeyID])
        )
        let authenticator = FakeDeviceKeyAuthenticator(
            attestation: .success(OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation))
        )
        let (client, _, keyStore) = makeClient(frontend: frontend, authenticator: authenticator)

        // When
        try await client.enrollDevice(name: "My iPhone")

        // Then the new server id is paired with the local key handle
        let stored = await keyStore.stored
        #expect(stored == OryStoredDeviceKey(clientKeyID: Fixture.attestedClientKeyID, localKeyID: "apple-key", userVerification: .none, identityID: "identity-1"))
        #expect(await frontend.submittedDeviceName == "My iPhone")
    }

    @Test("enrollDevice attests over the bare server nonce")
    func enrollUsesBareNonceChallenge() async throws {
        let authenticator = RecordingDeviceKeyAuthenticator()
        let (client, _, _) = makeClient(authenticator: authenticator)

        try await client.enrollDevice(name: "My iPhone")

        // A non-PIN key attests the raw nonce (DeviceEnrollmentChallenge.fake), unbound.
        #expect(await authenticator.attestChallenge == Data("nonce".utf8))
    }

    @Test("enrollDevice with a PIN binds the transport key into the attestation challenge")
    func enrollWithPINBindsTransportKeyIntoChallenge() async throws {
        let frontend = FakeFrontendRepository(pinSecretToSeal: Data(repeating: 9, count: 32), pinClientKeyID: Fixture.attestedClientKeyID)
        let authenticator = RecordingDeviceKeyAuthenticator()
        let (client, _, _) = makeClient(frontend: frontend, authenticator: authenticator)

        try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))

        // The server derives the attestation challenge as SHA256(nonce ‖ transport_public_key)
        // for PIN keys; the client must attest over exactly that, never the bare nonce.
        let nonce = Data("nonce".utf8) // DeviceEnrollmentChallenge.fake
        let transportKey = try #require(await frontend.submittedTransportPublicKey)
        let expected = Data(SHA256.hash(data: nonce + transportKey))
        #expect(await authenticator.attestChallenge == expected)
        #expect(await authenticator.attestChallenge != nonce)
    }

    @Test("enrollDevice selects its own attested key when other keys exist")
    func enrollWithExistingKeys() async throws {
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake()),
            submitEnrollment: .success(["other-device", Fixture.attestedClientKeyID])
        )
        let (client, _, keyStore) = makeClient(frontend: frontend)

        try await client.enrollDevice(name: "My iPhone")

        #expect(await keyStore.stored?.clientKeyID == Fixture.attestedClientKeyID)
    }

    @Test("enrollDevice throws unavailable on a device that cannot attest")
    func enrollUnavailable() async throws {
        let (client, _, keyStore) = makeClient(authenticator: FakeDeviceKeyAuthenticator(isAvailable: false))

        do {
            try await client.enrollDevice(name: "x")
            Issue.record("expected enrollDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationUnavailable)
        }
        #expect(await keyStore.stored == nil)
    }

    @Test("enrollDevice without a session throws notAuthenticated")
    func enrollNotAuthenticated() async throws {
        let (client, _, _) = makeClient(token: nil)

        do {
            try await client.enrollDevice(name: "x")
            Issue.record("expected enrollDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isNotAuthenticated)
        }
    }

    // MARK: - Step-up

    @Test("authenticateWithDevice signs for the stored server key and stores the AAL2 token")
    func stepUpStoresUpgradedToken() async throws {
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal1)),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2"))
        )
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv-key", localKeyID: "apple-key", userVerification: .none, identityID: "identity-1"))
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore)

        let authenticated = try await client.authenticateWithDevice()

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(await frontend.submittedClientKeyID == "srv-key")
        #expect(try await storage.sessionToken() == "ory_st_aal2")
    }

    @Test("authenticateWithDevice returns the current session without stepping up when already AAL2")
    func stepUpNoOpWhenAlreadyAAL2() async throws {
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal2))
        )
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv-key", localKeyID: "apple-key", userVerification: .none, identityID: "identity-1"))
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        let authenticated = try await client.authenticateWithDevice()

        // Already AAL2: no login flow is created or submitted (that would 400 with
        // session_already_available); the current session is returned as-is.
        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(await frontend.submitCallCount == 0)
    }

    @Test("authenticateWithDevice throws notEnrolled when this device has no key")
    func stepUpNotEnrolled() async throws {
        let (client, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: nil))

        do {
            _ = try await client.authenticateWithDevice()
            Issue.record("expected authenticateWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
    }

    @Test("authenticateWithDevice steps up when whoami reports the session needs a second factor")
    func stepUpWhenWhoamiRequiresSecondFactor() async throws {
        // Regression: whoami on an AAL1 session whose identity now requires AAL2 (e.g. right
        // after enrolling a device key) returns secondFactorRequired. That must trigger the
        // step-up, not abort it.
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2"))
        )
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv-key", localKeyID: "apple-key", userVerification: .none, identityID: "identity-1"))
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore)

        let authenticated = try await client.authenticateWithDevice()

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(await frontend.submittedClientKeyID == "srv-key")
        #expect(try await storage.sessionToken() == "ory_st_aal2")
    }

    @Test("authenticateWithDevice on a PIN key needing AAL2 throws pinRequired")
    func stepUpPINKeyNeedsPIN() async throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(currentSession: .failure(.secondFactorRequired))
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        do {
            _ = try await client.authenticateWithDevice()
            Issue.record("expected authenticateWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationPINRequired)
        }
        #expect(await frontend.submitCallCount == 0)
    }

    // MARK: - Step-up with PIN

    @Test("authenticateWithDevice(pin:) steps up with the device signature and pin_proof")
    func stepUpWithPINSubmitsProof() async throws {
        let secret = Data(repeating: 5, count: 32)
        let protected = try vault.protect(pinSecret: secret, pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2"))
        )
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore)

        let authenticated = try await client.authenticateWithDevice(pin: "1234")

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(try await storage.sessionToken() == "ory_st_aal2")
        // The step-up submitted the pin_proof over the login nonce (DeviceLoginChallenge.fake).
        let expected = vault.proof(pinSecret: secret, clientKeyID: "srv", nonce: Data("nonce".utf8))
        #expect(await frontend.submittedPINProof == expected)
    }

    @Test("authenticateWithDevice(pin:) with a wrong PIN submits a wrong proof and maps the server rejection to invalidPIN")
    func stepUpWithWrongPIN() async throws {
        // A wrong PIN must not be detectable on the device: the client submits a
        // wrong-but-well-formed pin_proof, and only the server — which counts the attempt
        // toward pin_max_attempts — rejects it.
        let secret = Data(repeating: 1, count: 32)
        let protected = try vault.protect(pinSecret: secret, pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .failure(Self.serverRejectsProof)
        )
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        do {
            _ = try await client.authenticateWithDevice(pin: "0000")
            Issue.record("expected authenticateWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationInvalidPIN)
        }

        // The attempt reached the server: exactly one submission, carrying a well-formed
        // proof that is not the correct one.
        #expect(await frontend.submitCallCount == 1)
        let submitted = try #require(await frontend.submittedPINProof)
        #expect(submitted.count == 32)
        let correct = vault.proof(pinSecret: secret, clientKeyID: "srv", nonce: Data("nonce".utf8))
        #expect(submitted != correct)
    }

    @Test("a server rejection without a submitted pin_proof is not mapped to invalidPIN")
    func stepUpServerRejectionWithoutPINStaysServerError() async throws {
        // The same 400 can mean a bad signature on a signature-only key; only the PIN
        // paths may reinterpret it as a wrong PIN.
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .none, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .failure(Self.serverRejectsProof)
        )
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        do {
            _ = try await client.authenticateWithDevice()
            Issue.record("expected authenticateWithDevice to throw")
        } catch let error as OryClientError {
            #expect(!error.isDeviceAuthenticationInvalidPIN)
            if case let .server(status, _, _) = error {
                #expect(status == 400)
            } else {
                Issue.record("expected the server error to pass through, got \(error)")
            }
        }
    }

    @Test("authenticateWithDevice(pin:) ignores the PIN on a signature-only key")
    func stepUpWithPINOnPlainKey() async throws {
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .none, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2"))
        )
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore)

        let authenticated = try await client.authenticateWithDevice(pin: "1234")

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(try await storage.sessionToken() == "ory_st_aal2")
        #expect(await frontend.submittedClientKeyID == "srv")
        #expect(await frontend.submittedPINProof == nil)
    }

    // MARK: - Removal

    @Test("removeDevice steps up, removes the server key, and clears local storage")
    func removeClearsStorage() async throws {
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal1)),
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2")),
            removalFlow: .success(URL(string: "https://ory.test/settings")!),
            submitRemoval: .success(())
        )
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv-key", localKeyID: "apple-key", userVerification: .none, identityID: "identity-1"))
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        try await client.removeDevice()

        #expect(await frontend.submittedClientKeyID == "srv-key")
        #expect(await keyStore.clearCallCount == 1)
        #expect(await keyStore.stored == nil)
    }

    // MARK: - Enrolled state

    @Test("deviceEnrollment reflects whether a key is stored")
    func deviceEnrollmentReflectsStorage() async throws {
        let (enrolled, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "k", localKeyID: "l", userVerification: .none, identityID: "identity-1")))
        let (notEnrolled, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: nil))

        #expect(try await enrolled.deviceEnrollment() == .enrolled(.none))
        #expect(try await notEnrolled.deviceEnrollment() == .notEnrolled)
    }

    // MARK: - PIN (1FA)

    @Test("enrollDevice with a PIN opens the sealed secret and stores it protected by the PIN")
    func enrollWithPINStoresProtectedSecret() async throws {
        // Given a server (fake) that seals this pin_secret to the device transport key
        let sealedSecret = Data(repeating: 9, count: 32)
        let frontend = FakeFrontendRepository(pinSecretToSeal: sealedSecret, pinClientKeyID: Fixture.attestedClientKeyID)
        let (client, _, keyStore) = makeClient(frontend: frontend)

        // When
        try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))

        // Then the PIN key is stored and the secret round-trips back through the PIN
        let stored = try #require(await keyStore.stored)
        #expect(stored.clientKeyID == Fixture.attestedClientKeyID)
        let protected = try #require(stored.pinSecret)
        #expect(try vault.unlock(protected, pinString: "1234") == sealedSecret)
    }

    @Test("loginWithDevice(pin:) unlocks, signs, and submits the correct pin_proof")
    func loginWithPINSubmitsProof() async throws {
        let secret = Data(repeating: 5, count: 32)
        let protected = try vault.protect(pinSecret: secret, pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .success(.fake(token: "ory_st_pin"))
        )
        let (client, storage, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore)

        _ = try await client.loginWithDevice(pin: "1234")

        #expect(await frontend.submittedClientKeyID == "srv")
        #expect(try await storage.sessionToken() == "ory_st_pin")
        // The submitted proof matches HMAC over the login nonce (DeviceLoginChallenge.fake).
        let expected = vault.proof(pinSecret: secret, clientKeyID: "srv", nonce: Data("nonce".utf8))
        #expect(await frontend.submittedPINProof == expected)
    }

    @Test("loginWithDevice(pin:) with a wrong PIN submits a wrong proof and maps the server rejection to invalidPIN")
    func loginWithWrongPIN() async throws {
        // The wrong PIN yields a wrong-but-well-formed proof that is submitted, so the
        // server's pin_max_attempts counter advances; the client never judges the PIN.
        let secret = Data(repeating: 1, count: 32)
        let protected = try vault.protect(pinSecret: secret, pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(
            loginChallenge: .success(.fake()),
            submitDeviceLogin: .failure(Self.serverRejectsProof)
        )
        let (client, _, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore)

        do {
            _ = try await client.loginWithDevice(pin: "0000")
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationInvalidPIN)
        }

        #expect(await frontend.submitCallCount == 1)
        let submitted = try #require(await frontend.submittedPINProof)
        #expect(submitted.count == 32)
        let correct = vault.proof(pinSecret: secret, clientKeyID: "srv", nonce: Data("nonce".utf8))
        #expect(submitted != correct)
    }

    @Test("forgetDevice deletes the sealing key behind stored PIN material")
    func forgetDeletesSealingKey() async throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "1234")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1"))
        let (client, _, _) = makeClient(keyStore: keyStore)

        try await client.forgetDevice()

        // The artifacts are gone, so the per-seal Secure Enclave key has nothing left to
        // protect and must not linger in the Keychain.
        #expect(await keyStore.stored == nil)
        #expect(sealingKeys.deletedTags == [protected.sealingKeyTag])
    }

    @Test("re-enrolling a PIN deletes the sealing key of the replaced material")
    func reenrollDeletesReplacedSealingKey() async throws {
        let oldProtected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "old", localKeyID: "apple", pinSecret: oldProtected, userVerification: .pin, identityID: "identity-1"))
        let frontend = FakeFrontendRepository(pinSecretToSeal: Data(repeating: 9, count: 32), pinClientKeyID: Fixture.attestedClientKeyID)
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))

        let stored = try #require(await keyStore.stored)
        #expect(stored.clientKeyID == Fixture.attestedClientKeyID)
        #expect(sealingKeys.deletedTags == [oldProtected.sealingKeyTag])
        // The new material's sealing key is the one that remains usable.
        #expect(try vault.unlock(#require(stored.pinSecret), pinString: "1234") == Data(repeating: 9, count: 32))
    }

    @Test("deviceEnrollment reports PIN only for a key that carries PIN material")
    func deviceEnrollmentReflectsPINKey() async throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "1234")
        let (pinKey, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "k", localKeyID: "l", pinSecret: protected, userVerification: .pin, identityID: "identity-1")))
        let (plainKey, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "k", localKeyID: "l", userVerification: .none, identityID: "identity-1")))
        let (noKey, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: nil))

        #expect(try await pinKey.deviceEnrollment() == .enrolled(.pin))
        #expect(try await plainKey.deviceEnrollment() != .enrolled(.pin))
        #expect(try await noKey.deviceEnrollment() != .enrolled(.pin))
    }

    @Test("loginWithDevice throws notEnrolled for a possession-only key", arguments: [nil, "1234"] as [String?])
    func loginWithPossessionOnlyKey(pin: String?) async throws {
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .none, identityID: "identity-1"))
        let frontend = FakeFrontendRepository()
        let (client, _, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore)

        do {
            _ = try await client.loginWithDevice(pin: pin)
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
        #expect(await frontend.submitCallCount == 0)
    }

    // MARK: - PIN reset (recovery)

    @Test("resetDevicePIN leaves the assurance-level decision to the server")
    func resetPINSurfacesTheServersAALDemand() async throws {
        // The old PIN is never part of a rotation, so the client must not refuse one locally:
        // whether this session may change settings is the project's policy. Here the server
        // rejects the settings flow, and that rejection is what reaches the caller — not a
        // locally invented deviceAuthenticationPINRequired.
        let oldProtected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: oldProtected, userVerification: .pin, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            enrollmentChallenge: .failure(.secondFactorRequired)
        )
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        do {
            try await client.resetDevicePIN(newPin: "5678")
            Issue.record("expected resetDevicePIN to throw")
        } catch let error as OryClientError {
            #expect(error.isSecondFactorRequired)
        }
        // The refusal came from the server: the client did reach it.
        #expect(await frontend.receivedSessionToken != nil)
        // And the stored secret still opens with the old PIN.
        let protected = try #require(await keyStore.stored?.pinSecret)
        #expect(try vault.unlock(protected, pinString: "0000") == Data(repeating: 1, count: 32))
    }

    @Test("resetDevicePIN rotates with one submit and no step-up login flow")
    func resetPINRotatesWithoutSteppingUp() async throws {
        // A rotation is one settings submit. It must not create an aal2 login flow (already
        // being AAL2 makes that 400 with session_already_available) and must not gate itself
        // on a whoami — this fake would fail one, proving none is made.
        let freshSecret = Data(repeating: 7, count: 32)
        let oldProtected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: oldProtected, userVerification: .pin, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.secondFactorRequired),
            rotatedPINSecretToSeal: freshSecret
        )
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        try await client.resetDevicePIN(newPin: "5678")

        #expect(await frontend.submitCallCount == 1)
        let protected = try #require(await keyStore.stored?.pinSecret)
        #expect(try vault.unlock(protected, pinString: "5678") == freshSecret)
    }

    @Test("resetDevicePIN signs the raw nonce ‖ transport key, not a hash")
    func resetPINSignsRawConcatChallenge() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(
                clientKeyID: "srv",
                localKeyID: "apple",
                pinSecret: try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000"),
                userVerification: .pin, identityID: "identity-1"
            )
        )
        // Already AAL2, so the only assertion made is the rotation one under test.
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal2))
        )
        let authenticator = RecordingDeviceKeyAuthenticator()
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore, authenticator: authenticator)

        try await client.resetDevicePIN(newPin: "5678")

        // The rotation assertion covers nonce ‖ transport_public_key as a raw concatenation —
        // the backend hashes it itself, so the client must not.
        let nonce = Data("nonce".utf8) // DeviceEnrollmentChallenge.fake
        let transportKey = try #require(await frontend.submittedTransportPublicKey)
        var expected = nonce
        expected.append(transportKey)
        #expect(await authenticator.assertChallenge == expected)
        #expect(await authenticator.assertChallenge?.count == nonce.count + transportKey.count)
    }

    @Test("resetDevicePIN throws notEnrolled when the stored key has no PIN")
    func resetPINNoPINKey() async throws {
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .none, identityID: "identity-1"))
        let frontend = FakeFrontendRepository()
        let (client, _, _) = makeClient(frontend: frontend, keyStore: keyStore)

        do {
            try await client.resetDevicePIN(newPin: "5678")
            Issue.record("expected resetDevicePIN to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
        #expect(await frontend.submitCallCount == 0)
    }

    @Test("resetDevicePIN throws notEnrolled when this device has no key")
    func resetPINNotEnrolled() async throws {
        let (client, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: nil))

        do {
            try await client.resetDevicePIN(newPin: "5678")
            Issue.record("expected resetDevicePIN to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
    }

    @Test("resetDevicePIN without a session throws notAuthenticated")
    func resetPINNotAuthenticated() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(
                clientKeyID: "srv",
                localKeyID: "apple",
                pinSecret: try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000"),
                userVerification: .pin, identityID: "identity-1"
            )
        )
        let (client, _, _) = makeClient(token: nil, keyStore: keyStore)

        do {
            try await client.resetDevicePIN(newPin: "5678")
            Issue.record("expected resetDevicePIN to throw")
        } catch let error as OryClientError {
            #expect(error.isNotAuthenticated)
        }
    }

    // MARK: - Availability of methods

    @Test("availableDeviceAuthenticationMethods offers PIN and biometric when both are available")
    func availableMethodsWithBiometrics() {
        let (client, _, _) = makeClient(
            authenticator: FakeDeviceKeyAuthenticator(isAvailable: true),
            biometric: FakeBiometricAuthenticator(isAvailable: true)
        )
        #expect(client.availableDeviceAuthenticationMethods == [.pin, .biometric])
    }

    @Test("availableDeviceAuthenticationMethods omits biometric when the device cannot use it")
    func availableMethodsWithoutBiometrics() {
        let (client, _, _) = makeClient(
            authenticator: FakeDeviceKeyAuthenticator(isAvailable: true),
            biometric: FakeBiometricAuthenticator(isAvailable: false)
        )
        #expect(client.availableDeviceAuthenticationMethods == [.pin])
    }

    @Test("availableDeviceAuthenticationMethods is empty when device authentication is unavailable")
    func availableMethodsWithoutDeviceAuth() {
        let (client, _, _) = makeClient(
            authenticator: FakeDeviceKeyAuthenticator(isAvailable: false),
            biometric: FakeBiometricAuthenticator(isAvailable: true)
        )
        #expect(client.availableDeviceAuthenticationMethods.isEmpty)
    }

    @Test("biometryType reflects the biometric authenticator")
    func biometryTypeReflectsAuthenticator() {
        let (client, _, _) = makeClient(biometric: FakeBiometricAuthenticator(biometryType: .touchID))
        #expect(client.biometryType == .touchID)
    }

    // MARK: - Biometric enrollment

    @Test("enrollDevice with biometrics stores a platform key and declares platform verification")
    func biometricEnrollStoresPlatformKey() async throws {
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake()),
            submitEnrollment: .success([Fixture.attestedClientKeyID])
        )
        let biometric = FakeBiometricAuthenticator()
        let authenticator = FakeDeviceKeyAuthenticator(
            attestation: .success(OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation))
        )
        let (client, _, keyStore) = makeClient(frontend: frontend, authenticator: authenticator, biometric: biometric)

        try await client.enrollDevice(name: "My iPhone", protection: .biometrics)

        let stored = try #require(await keyStore.stored)
        #expect(stored == OryStoredDeviceKey(clientKeyID: Fixture.attestedClientKeyID, localKeyID: "apple-key", userVerification: .platform, identityID: "identity-1"))
        #expect(await frontend.submittedUserVerification == .platform)
        // A biometric key has no PIN transport key and no sealed secret.
        #expect(await frontend.submittedTransportPublicKey == nil)
        // The user's biometric was confirmed and bound to the attested key, without a sign-in prompt.
        #expect(await biometric.enrolledKeyIDs == ["apple-key"])
        #expect(await biometric.evaluateCallCount == 0)
    }

    @Test("enrollDevice with biometrics removes the biometric binding when registration fails")
    func biometricEnrollRegistrationFailureRemovesBinding() async throws {
        // Given a server that rejects the enrollment.
        let frontend = FakeFrontendRepository(
            enrollmentChallenge: .success(.fake()),
            submitEnrollment: .failure(.server(status: 400, id: nil, messages: []))
        )
        let biometric = FakeBiometricAuthenticator()
        let authenticator = FakeDeviceKeyAuthenticator(
            attestation: .success(OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation))
        )
        let (client, _, keyStore) = makeClient(frontend: frontend, authenticator: authenticator, biometric: biometric)

        // When the user enrolls biometrics.
        await #expect(throws: OryClientError.self) {
            try await client.enrollDevice(name: "My iPhone", protection: .biometrics)
        }

        // Then nothing is stored and the binding created for the attested key is removed.
        #expect(await keyStore.stored == nil)
        #expect(await biometric.enrolledKeyIDs == ["apple-key"])
        #expect(await biometric.removedKeyIDs == ["apple-key"])
    }

    @Test("enrollDevice with biometrics shows the configured enrollment prompt")
    func biometricEnrollUsesConfiguredReason() async throws {
        let biometric = FakeBiometricAuthenticator()
        let (client, _, _) = makeClient(biometric: biometric, enrollReason: "Set up sign-in for Acme Bank.")

        try await client.enrollDevice(name: "My iPhone", protection: .biometrics)

        #expect(await biometric.lastReason == "Set up sign-in for Acme Bank.")
    }

    @Test("enrollDevice with biometrics attests over the bare server nonce")
    func biometricEnrollUsesBareNonceChallenge() async throws {
        let authenticator = RecordingDeviceKeyAuthenticator()
        let (client, _, _) = makeClient(authenticator: authenticator)

        try await client.enrollDevice(name: "My iPhone", protection: .biometrics)

        // Like a plain key, a biometric key attests the raw nonce — no transport-key binding.
        #expect(await authenticator.attestChallenge == Data("nonce".utf8))
    }

    @Test("enrollDevice with biometrics throws when biometrics are unavailable, before any network call")
    func biometricEnrollUnavailable() async throws {
        let frontend = FakeFrontendRepository()
        let (client, _, keyStore) = makeClient(
            frontend: frontend,
            biometric: FakeBiometricAuthenticator(isAvailable: false)
        )

        do {
            try await client.enrollDevice(name: "x", protection: .biometrics)
            Issue.record("expected enrollDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationBiometricsUnavailable)
        }
        #expect(await keyStore.stored == nil)
        #expect(await frontend.submitCallCount == 0)
    }

    @Test("enrollDevice with biometrics surfaces a cancelled prompt without enrolling")
    func biometricEnrollCancelled() async throws {
        let frontend = FakeFrontendRepository()
        let biometric = FakeBiometricAuthenticator(prompt: .failure(.deviceAuthenticationCancelled))
        let (client, _, keyStore) = makeClient(frontend: frontend, biometric: biometric)

        do {
            try await client.enrollDevice(name: "x", protection: .biometrics)
            Issue.record("expected enrollDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationCancelled)
        }
        #expect(await keyStore.stored == nil)
        #expect(await frontend.submitCallCount == 0)
    }

    // MARK: - Biometric first-factor login

    @Test("loginWithDevice on a biometric key signs in with the signature only and stores the token")
    func biometricLoginSignatureOnly() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(submitDeviceLogin: .success(.fake(token: "ory_st_bio")))
        let biometric = FakeBiometricAuthenticator()
        let (client, storage, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore, biometric: biometric)

        let authenticated = try await client.loginWithDevice()

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(try await storage.sessionToken() == "ory_st_bio")
        #expect(await frontend.submittedClientKeyID == "srv-bio")
        // The server forbids a pin_proof on a signature-only key; the client must send none.
        #expect(await frontend.firstFactorHadPINProof == false)
        #expect(await frontend.submittedPINProof == nil)
        #expect(await biometric.evaluateCallCount == 1)
    }

    @Test("loginWithDevice without a PIN throws pinRequired for a PIN key")
    func loginWithoutPINOnPINKey() async throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository()
        let biometric = FakeBiometricAuthenticator()
        let (client, _, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore, biometric: biometric)

        do {
            _ = try await client.loginWithDevice(pin: nil)
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationPINRequired)
        }
        #expect(await frontend.submitCallCount == 0)
        #expect(await biometric.evaluateCallCount == 0)
    }

    @Test("loginWithDevice(pin:) on a biometric key ignores the PIN and prompts biometrics")
    func biometricLoginIgnoresPIN() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(submitDeviceLogin: .success(.fake(token: "ory_st_bio")))
        let biometric = FakeBiometricAuthenticator()
        let (client, storage, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore, biometric: biometric)

        _ = try await client.loginWithDevice(pin: "1234")

        #expect(try await storage.sessionToken() == "ory_st_bio")
        #expect(await frontend.firstFactorHadPINProof == false)
        #expect(await biometric.evaluatedKeyIDs == ["apple"])
    }

    @Test("loginWithDevice on a biometric key throws biometricsUnavailable without submitting")
    func biometricLoginUnavailable() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository()
        let (client, _, _) = makeClient(
            token: nil,
            frontend: frontend,
            keyStore: keyStore,
            biometric: FakeBiometricAuthenticator(isAvailable: false)
        )

        do {
            _ = try await client.loginWithDevice()
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationBiometricsUnavailable)
        }
        #expect(await frontend.submitCallCount == 0)
    }

    @Test("loginWithDevice on a biometric key surfaces a cancelled prompt without submitting")
    func biometricLoginCancelled() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository()
        let biometric = FakeBiometricAuthenticator(prompt: .failure(.deviceAuthenticationCancelled))
        let (client, _, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore, biometric: biometric)

        do {
            _ = try await client.loginWithDevice()
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationCancelled)
        }
        #expect(await frontend.submitCallCount == 0)
    }

    @Test("loginWithDevice on a biometric key surfaces changed biometrics without submitting")
    func biometricLoginBiometricsChanged() async throws {
        // Given a biometric key whose binding no longer matches the device's biometrics.
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository()
        let biometric = FakeBiometricAuthenticator(evaluate: .failure(.deviceAuthenticationBiometricsChanged))
        let (client, storage, _) = makeClient(token: nil, frontend: frontend, keyStore: keyStore, biometric: biometric)

        // When the user signs in with biometrics.
        do {
            _ = try await client.loginWithDevice()
            Issue.record("expected loginWithDevice to throw")
        } catch let error as OryClientError {
            // Then the change is reported and nothing is signed or submitted.
            #expect(error.isDeviceAuthenticationBiometricsChanged)
        }
        #expect(await biometric.evaluatedKeyIDs == ["apple"])
        #expect(await frontend.submitCallCount == 0)
        #expect(try await storage.sessionToken() == nil)
    }

    // MARK: - Biometric step-up

    @Test("authenticateWithDevice on a biometric key steps a below-AAL2 session up and prompts biometrics")
    func biometricStepUp() async throws {
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal1)),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2"))
        )
        let biometric = FakeBiometricAuthenticator()
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore, biometric: biometric)

        let authenticated = try await client.authenticateWithDevice()

        #expect(authenticated.session.authenticatorAssuranceLevel == .aal2)
        #expect(try await storage.sessionToken() == "ory_st_aal2")
        // Step-up sends no pin_proof for a platform key.
        #expect(await frontend.submittedPINProof == nil)
        #expect(await biometric.evaluateCallCount == 1)
    }

    @Test("authenticateWithDevice on a biometric key surfaces changed biometrics without stepping up")
    func biometricStepUpBiometricsChanged() async throws {
        // Given an AAL1 session and a biometric key whose binding no longer matches.
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let frontend = FakeFrontendRepository(currentSession: .success(Sample.session(assuranceLevel: .aal1)))
        let biometric = FakeBiometricAuthenticator(evaluate: .failure(.deviceAuthenticationBiometricsChanged))
        let (client, storage, _) = makeClient(frontend: frontend, keyStore: keyStore, biometric: biometric)

        // When the user steps up with biometrics.
        do {
            _ = try await client.authenticateWithDevice()
            Issue.record("expected authenticateWithDevice to throw")
        } catch let error as OryClientError {
            // Then the change is reported and the AAL1 token is kept.
            #expect(error.isDeviceAuthenticationBiometricsChanged)
        }
        #expect(await frontend.submitCallCount == 0)
        #expect(try await storage.sessionToken() == "ory_st_aal1")
    }

    @Test("forgetDevice removes the biometric binding of a biometric key")
    func forgetDeviceRemovesBiometricBinding() async throws {
        // Given an enrolled biometric key.
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv-bio", localKeyID: "apple", userVerification: .platform, identityID: "identity-1")
        )
        let biometric = FakeBiometricAuthenticator()
        let (client, _, _) = makeClient(keyStore: keyStore, biometric: biometric)

        // When the device is forgotten.
        try await client.forgetDevice()

        // Then the key and its binding are gone.
        #expect(await keyStore.stored == nil)
        #expect(await biometric.removedKeyIDs == ["apple"])
    }

    @Test("forgetDevice leaves the biometric authenticator alone for a PIN key")
    func forgetDeviceKeepsBiometricsForPINKey() async throws {
        // Given an enrolled PIN key.
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let keyStore = InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", pinSecret: protected, userVerification: .pin, identityID: "identity-1")
        )
        let biometric = FakeBiometricAuthenticator()
        let (client, _, _) = makeClient(keyStore: keyStore, biometric: biometric)

        // When the device is forgotten.
        try await client.forgetDevice()

        // Then no biometric binding is touched.
        #expect(await biometric.removedKeyIDs.isEmpty)
    }

    // MARK: - Enrolled state and gate isolation

    @Test("deviceEnrollment reports platform verification only for a biometric key")
    func deviceEnrollmentReflectsBiometricKey() async throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000")
        let (bio, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "k", localKeyID: "l", userVerification: .platform, identityID: "identity-1")
        ))
        let (pin, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(
            initial: OryStoredDeviceKey(clientKeyID: "k", localKeyID: "l", pinSecret: protected, userVerification: .pin, identityID: "identity-1")
        ))
        let (none, _, _) = makeClient(keyStore: InMemoryDeviceKeyStore(initial: nil))

        #expect(try await bio.deviceEnrollment() == .enrolled(.platform))
        #expect(try await pin.deviceEnrollment() != .enrolled(.platform))
        #expect(try await none.deviceEnrollment() != .enrolled(.platform))
    }

    @Test("PIN login does not trigger the biometric gate")
    func pinLoginDoesNotPromptBiometrics() async throws {
        let secret = Data(repeating: 9, count: 32)
        let frontend = FakeFrontendRepository(pinSecretToSeal: secret, pinClientKeyID: Fixture.attestedClientKeyID)
        // Enroll a PIN key so the store holds real sealed material.
        let biometric = FakeBiometricAuthenticator()
        let (client, _, _) = makeClient(frontend: frontend, biometric: biometric)
        try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))

        _ = try await client.loginWithDevice(pin: "1234")

        // A PIN key is not biometric-gated, so no prompt is ever shown.
        #expect(await biometric.evaluateCallCount == 0)
    }
}
