import Foundation
import Security
@testable import OryClient

extension DevicePINVault {
    /// Test convenience: the production API takes the secret and PIN as mutable, zeroized
    /// byte arrays; tests read better with literals.
    func protect(pinSecret: Data, pinString: String) throws -> OryProtectedPINSecret {
        var secret = Array(pinSecret)
        var pin = Array(pinString.utf8)
        return try protect(pinSecret: &secret, pin: &pin)
    }

    /// Test convenience mirroring ``protect(pinSecret:pinString:)``.
    func unlock(_ protected: OryProtectedPINSecret, pinString: String) throws -> Data {
        var pin = Array(pinString.utf8)
        return Data(try unlock(protected, pin: &pin))
    }
}

/// An in-memory ``OryDeviceKeyStore`` that records what was stored.
actor InMemoryDeviceKeyStore: OryDeviceKeyStore {

    nonisolated let deviceOperationScope = UUID().uuidString

    private(set) var stored: OryStoredDeviceKey?
    private(set) var clearCallCount = 0

    init(initial: OryStoredDeviceKey? = nil) {
        self.stored = initial
    }

    func enrolledKey() async throws -> OryStoredDeviceKey? { stored }

    func store(_ key: OryStoredDeviceKey) async throws { stored = key }

    func clear() async throws {
        clearCallCount += 1
        stored = nil
    }
}

/// A ``OryDeviceKeyAuthenticator`` that returns canned attestations and signatures without
/// touching the Secure Enclave, so orchestration can be tested off-device.
struct FakeDeviceKeyAuthenticator: OryDeviceKeyAuthenticator {

    var isAvailable: Bool = true
    var attestation: Result<OryDeviceKeyAttestation, OryClientError> = .success(
        OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation)
    )
    var signature: Result<Data, OryClientError> = .success(Data("signature".utf8))

    func attestNewKey(challenge: Data) async throws -> OryDeviceKeyAttestation {
        try attestation.get()
    }

    func generateAssertion(keyID: String, challenge: Data) async throws -> Data {
        try signature.get()
    }
}

/// A ``OryBiometricAuthenticator`` that records its prompts and bindings and returns a canned
/// outcome, so the biometric gate can be exercised without a real Face ID / Touch ID prompt.
actor FakeBiometricAuthenticator: OryBiometricAuthenticator {

    nonisolated let isAvailable: Bool
    nonisolated let biometryType: OryBiometryType
    private let promptResult: Result<Void, OryClientError>
    private let evaluateResult: Result<Void, OryClientError>

    private(set) var enrolledKeyIDs: [String] = []
    private(set) var evaluatedKeyIDs: [String] = []
    private(set) var removedKeyIDs: [String] = []
    private(set) var lastReason: String?

    var evaluateCallCount: Int { evaluatedKeyIDs.count }

    /// - Parameters:
    ///   - prompt: How the enrollment prompt and every evaluation prompt resolve.
    ///   - evaluate: How evaluation resolves once its prompt succeeded, for example
    ///     ``OryClientError/deviceAuthenticationBiometricsChanged``.
    init(
        isAvailable: Bool = true,
        biometryType: OryBiometryType = .faceID,
        prompt: Result<Void, OryClientError> = .success(()),
        evaluate: Result<Void, OryClientError> = .success(())
    ) {
        self.isAvailable = isAvailable
        self.biometryType = biometryType
        self.promptResult = prompt
        self.evaluateResult = evaluate
    }

    func enroll(keyID: String, reason: String) async throws {
        lastReason = reason
        try promptResult.get()
        enrolledKeyIDs.append(keyID)
    }

    func evaluate(keyID: String, reason: String) async throws {
        evaluatedKeyIDs.append(keyID)
        lastReason = reason
        try promptResult.get()
        try evaluateResult.get()
    }

    func removeEnrollment(keyID: String) async {
        removedKeyIDs.append(keyID)
    }
}

/// A ``OryDeviceKeyAuthenticator`` that records the challenge it was asked to attest or assert,
/// so tests can assert the client passed the exact bytes the server expects (e.g. the
/// transport-key-bound challenge at PIN enrollment).
actor RecordingDeviceKeyAuthenticator: OryDeviceKeyAuthenticator {

    nonisolated let isAvailable: Bool
    private let attestationResult: Result<OryDeviceKeyAttestation, OryClientError>
    private let signatureResult: Result<Data, OryClientError>

    private(set) var attestChallenge: Data?
    private(set) var assertChallenge: Data?

    init(
        isAvailable: Bool = true,
        attestation: Result<OryDeviceKeyAttestation, OryClientError> = .success(
            OryDeviceKeyAttestation(keyID: "apple-key", attestation: Fixture.deviceAttestation)
        ),
        signature: Result<Data, OryClientError> = .success(Data("signature".utf8))
    ) {
        self.isAvailable = isAvailable
        self.attestationResult = attestation
        self.signatureResult = signature
    }

    func attestNewKey(challenge: Data) async throws -> OryDeviceKeyAttestation {
        attestChallenge = challenge
        return try attestationResult.get()
    }

    func generateAssertion(keyID: String, challenge: Data) async throws -> Data {
        assertChallenge = challenge
        return try signatureResult.get()
    }
}
