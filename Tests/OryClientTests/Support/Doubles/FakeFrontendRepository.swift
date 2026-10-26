import CryptoKit
import Foundation
@testable import OryClient

/// Returns configured outcomes and records what it was called with. Used to test
/// ``OryClient`` orchestration without the network.
actor FakeFrontendRepository: SessionRepository, LoginRepository, RegistrationRepository, VerificationRepository, RecoveryRepository, SettingsRepository, DeviceAuthnRepository {

    private let currentSessionResult: Result<OrySession, OryClientError>
    private let revokeSessionResult: Result<Void, OryClientError>
    private let createLoginFlowResult: Result<OryFlow, OryClientError>
    private let getLoginFlowResult: Result<OryFlow, OryClientError>
    private let submitLoginResult: Result<LoginSubmissionOutcome, OryClientError>
    private let createRegistrationFlowResult: Result<OryFlow, OryClientError>
    private let getRegistrationFlowResult: Result<OryFlow, OryClientError>
    private let submitRegistrationResult: Result<RegistrationOutcome, OryClientError>
    private let createVerificationFlowResult: Result<OryFlow, OryClientError>
    private let getVerificationFlowResult: Result<OryFlow, OryClientError>
    private let submitVerificationResult: Result<VerificationOutcome, OryClientError>
    private let createRecoveryFlowResult: Result<OryFlow, OryClientError>
    private let getRecoveryFlowResult: Result<OryFlow, OryClientError>
    private let submitRecoveryResult: Result<RecoveryOutcome, OryClientError>
    private let createSettingsFlowResult: Result<OryFlow, OryClientError>
    private let getSettingsFlowResult: Result<OryFlow, OryClientError>
    private let submitSettingsResult: Result<SettingsOutcome, OryClientError>
    private let enrollmentChallengeResult: Result<DeviceEnrollmentChallenge, OryClientError>
    private let submitEnrollmentResult: Result<Set<String>, OryClientError>
    private let loginChallengeResult: Result<DeviceLoginChallenge, OryClientError>
    private let submitDeviceLoginResult: Result<DeviceLoginOutcome, OryClientError>
    private let removalFlowResult: Result<URL, OryClientError>
    private let submitRemovalResult: Result<Void, OryClientError>
    /// The `pin_secret` the fake seals to the device's transport key at PIN enrollment, and
    /// the client_key_id it reports as new — so a real `DevicePINVault` can open it in tests.
    private let pinSecretToSeal: Data
    private let pinClientKeyID: String
    private let concurrentEnrollmentKeyIDs: Set<String>
    /// The fresh `pin_secret` the fake re-seals on rotation. Distinct from `pinSecretToSeal`
    /// so a test can prove rotation stored the new secret, not the old one.
    private let rotatedPINSecretToSeal: Data
    /// The keys `listDeviceKeys` reports, as the server would list them in the settings flow.
    private let deviceKeyRecords: [DeviceKeyRecord]
    private let afterDeviceMutation: @Sendable () async throws -> Void

    private(set) var receivedSessionToken: String?
    private(set) var submitCallCount = 0
    private(set) var receivedLoginFlowOptions: OryLoginFlowOptions?
    private(set) var receivedLoginSessionToken: String?
    private(set) var submittedDeviceName: String?
    private(set) var submittedClientKeyID: String?
    private(set) var submittedPINProof: Data?
    private(set) var submittedTransportPublicKey: Data?
    private(set) var submittedUserVerification: OryDeviceUserVerification?
    /// Whether `submitDeviceFirstFactorLogin` was called with a non-nil `pinProof`.
    private(set) var firstFactorHadPINProof: Bool?

    init(
        currentSession: Result<OrySession, OryClientError> = .failure(.notAuthenticated),
        revokeSession: Result<Void, OryClientError> = .success(()),
        createLoginFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getLoginFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitLogin: Result<LoginSubmissionOutcome, OryClientError> = .failure(.notAuthenticated),
        createRegistrationFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getRegistrationFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitRegistration: Result<RegistrationOutcome, OryClientError> = .failure(.notAuthenticated),
        createVerificationFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getVerificationFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitVerification: Result<VerificationOutcome, OryClientError> = .failure(.notAuthenticated),
        createRecoveryFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getRecoveryFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitRecovery: Result<RecoveryOutcome, OryClientError> = .failure(.notAuthenticated),
        createSettingsFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getSettingsFlow: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitSettings: Result<SettingsOutcome, OryClientError> = .failure(.notAuthenticated),
        enrollmentChallenge: Result<DeviceEnrollmentChallenge, OryClientError> = .success(.fake()),
        submitEnrollment: Result<Set<String>, OryClientError> = .success([Fixture.attestedClientKeyID]),
        loginChallenge: Result<DeviceLoginChallenge, OryClientError> = .success(.fake()),
        submitDeviceLogin: Result<DeviceLoginOutcome, OryClientError> = .success(.fake()),
        removalFlow: Result<URL, OryClientError> = .success(URL(string: "https://ory.test/settings")!),
        submitRemoval: Result<Void, OryClientError> = .success(()),
        pinSecretToSeal: Data = Data(repeating: 9, count: 32),
        pinClientKeyID: String = Fixture.attestedClientKeyID,
        concurrentEnrollmentKeyIDs: Set<String> = [],
        rotatedPINSecretToSeal: Data = Data(repeating: 7, count: 32),
        deviceKeyRecords: [DeviceKeyRecord] = [],
        afterDeviceMutation: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.deviceKeyRecords = deviceKeyRecords
        self.afterDeviceMutation = afterDeviceMutation
        self.currentSessionResult = currentSession
        self.revokeSessionResult = revokeSession
        self.createLoginFlowResult = createLoginFlow
        self.getLoginFlowResult = getLoginFlow
        self.submitLoginResult = submitLogin
        self.createRegistrationFlowResult = createRegistrationFlow
        self.getRegistrationFlowResult = getRegistrationFlow
        self.submitRegistrationResult = submitRegistration
        self.createVerificationFlowResult = createVerificationFlow
        self.getVerificationFlowResult = getVerificationFlow
        self.submitVerificationResult = submitVerification
        self.createRecoveryFlowResult = createRecoveryFlow
        self.getRecoveryFlowResult = getRecoveryFlow
        self.submitRecoveryResult = submitRecovery
        self.createSettingsFlowResult = createSettingsFlow
        self.getSettingsFlowResult = getSettingsFlow
        self.submitSettingsResult = submitSettings
        self.enrollmentChallengeResult = enrollmentChallenge
        self.submitEnrollmentResult = submitEnrollment
        self.loginChallengeResult = loginChallenge
        self.submitDeviceLoginResult = submitDeviceLogin
        self.removalFlowResult = removalFlow
        self.submitRemovalResult = submitRemoval
        self.pinSecretToSeal = pinSecretToSeal
        self.pinClientKeyID = pinClientKeyID
        self.concurrentEnrollmentKeyIDs = concurrentEnrollmentKeyIDs
        self.rotatedPINSecretToSeal = rotatedPINSecretToSeal
    }

    func currentSession(sessionToken: String) async throws -> OrySession {
        receivedSessionToken = sessionToken
        return try currentSessionResult.get()
    }

    func revokeSession(sessionToken: String) async throws {
        receivedSessionToken = sessionToken
        submitCallCount += 1
        try revokeSessionResult.get()
    }

    func createLoginFlow(options: OryLoginFlowOptions, sessionToken: String?) async throws -> OryFlow {
        receivedLoginFlowOptions = options
        receivedLoginSessionToken = sessionToken
        return try createLoginFlowResult.get()
    }

    func getLoginFlow(id: String) async throws -> OryFlow {
        try getLoginFlowResult.get()
    }

    func submitLogin(url: URL, fields: [String: String], sessionToken: String?) async throws -> LoginSubmissionOutcome {
        submitCallCount += 1
        receivedLoginSessionToken = sessionToken
        return try submitLoginResult.get()
    }

    func createRegistrationFlow() async throws -> OryFlow {
        try createRegistrationFlowResult.get()
    }

    func getRegistrationFlow(id: String) async throws -> OryFlow {
        try getRegistrationFlowResult.get()
    }

    func submitRegistration(url: URL, fields: [String: String], sessionToken: String?) async throws -> RegistrationOutcome {
        submitCallCount += 1
        return try submitRegistrationResult.get()
    }

    func createVerificationFlow() async throws -> OryFlow {
        try createVerificationFlowResult.get()
    }

    func getVerificationFlow(id: String) async throws -> OryFlow {
        try getVerificationFlowResult.get()
    }

    func submitVerification(url: URL, fields: [String: String]) async throws -> VerificationOutcome {
        submitCallCount += 1
        return try submitVerificationResult.get()
    }

    func createRecoveryFlow() async throws -> OryFlow {
        try createRecoveryFlowResult.get()
    }

    func getRecoveryFlow(id: String) async throws -> OryFlow {
        try getRecoveryFlowResult.get()
    }

    func submitRecovery(url: URL, fields: [String: String]) async throws -> RecoveryOutcome {
        submitCallCount += 1
        return try submitRecoveryResult.get()
    }

    func createSettingsFlow(sessionToken: String) async throws -> OryFlow {
        receivedSessionToken = sessionToken
        return try createSettingsFlowResult.get()
    }

    func getSettingsFlow(id: String, sessionToken: String) async throws -> OryFlow {
        receivedSessionToken = sessionToken
        return try getSettingsFlowResult.get()
    }

    func submitSettings(url: URL, fields: [String: String], sessionToken: String) async throws -> SettingsOutcome {
        submitCallCount += 1
        receivedSessionToken = sessionToken
        return try submitSettingsResult.get()
    }

    func createDeviceEnrollmentChallenge(sessionToken: String) async throws -> DeviceEnrollmentChallenge {
        receivedSessionToken = sessionToken
        return try enrollmentChallengeResult.get()
    }

    func submitDeviceEnrollment(url: URL, sessionToken: String, attestation: Data, deviceName: String, userVerification: OryDeviceUserVerification) async throws -> Set<String> {
        submitCallCount += 1
        submittedDeviceName = deviceName
        submittedUserVerification = userVerification
        let result = try submitEnrollmentResult.get()
        try await afterDeviceMutation()
        return result
    }

    func createDeviceLoginChallenge(sessionToken: String) async throws -> DeviceLoginChallenge {
        receivedSessionToken = sessionToken
        return try loginChallengeResult.get()
    }

    func submitDeviceLogin(url: URL, sessionToken: String, clientKeyID: String, signature: Data, pinProof: Data?) async throws -> DeviceLoginOutcome {
        submitCallCount += 1
        submittedClientKeyID = clientKeyID
        submittedPINProof = pinProof
        return try submitDeviceLoginResult.get()
    }

    func createDeviceRemovalFlow(sessionToken: String) async throws -> URL {
        receivedSessionToken = sessionToken
        return try removalFlowResult.get()
    }

    func listDeviceKeys(sessionToken: String) async throws -> DeviceKeyListing {
        receivedSessionToken = sessionToken
        return DeviceKeyListing(submitURL: try removalFlowResult.get(), keys: deviceKeyRecords)
    }

    func submitDeviceRemoval(url: URL, sessionToken: String, clientKeyID: String) async throws {
        submitCallCount += 1
        submittedClientKeyID = clientKeyID
        try submitRemovalResult.get()
        try await afterDeviceMutation()
    }

    func submitDevicePINEnrollment(
        url: URL,
        sessionToken: String,
        attestation: Data,
        deviceName: String,
        transportPublicKey: Data
    ) async throws -> DevicePINEnrollmentResult {
        submitCallCount += 1
        submittedDeviceName = deviceName
        submittedTransportPublicKey = transportPublicKey
        let result = DevicePINEnrollmentResult(
            keyIDs: concurrentEnrollmentKeyIDs.union([pinClientKeyID]),
            sealed: try sealPINSecret(pinSecretToSeal, to: transportPublicKey, clientKeyID: pinClientKeyID)
        )
        try await afterDeviceMutation()
        return result
    }

    func createDeviceFirstFactorLoginChallenge() async throws -> DeviceLoginChallenge {
        try loginChallengeResult.get()
    }

    func submitDeviceFirstFactorLogin(url: URL, clientKeyID: String, signature: Data, pinProof: Data?) async throws -> DeviceLoginOutcome {
        submitCallCount += 1
        submittedClientKeyID = clientKeyID
        submittedPINProof = pinProof
        firstFactorHadPINProof = pinProof != nil
        return try submitDeviceLoginResult.get()
    }

    func submitDevicePINRotation(
        url: URL,
        sessionToken: String,
        clientKeyID: String,
        signature: Data,
        transportPublicKey: Data
    ) async throws -> SealedPINSecret {
        submitCallCount += 1
        submittedClientKeyID = clientKeyID
        submittedTransportPublicKey = transportPublicKey
        let result = try sealPINSecret(rotatedPINSecretToSeal, to: transportPublicKey, clientKeyID: clientKeyID)
        try await afterDeviceMutation()
        return result
    }

    /// Emulates the server: HPKE-seals `secret` to the device's transport public key with the
    /// client_key_id as AAD, exactly as the backend does for one-time pin_secret delivery.
    /// Uses the package's own `OryHPKE` sender, whose interop with CryptoKit's reference
    /// implementation is pinned by `OryHPKETests`.
    private func sealPINSecret(_ secret: Data, to transportPublicKey: Data, clientKeyID: String) throws -> SealedPINSecret {
        let info = Data("ory/deviceauthn/pin-secret/v1".utf8)
        let sealed = try OryHPKE.seal(
            secret,
            recipientPublicKey: transportPublicKey,
            info: info,
            authenticating: Data(clientKeyID.utf8)
        )
        return SealedPINSecret(enc: sealed.encapsulatedKey, ciphertext: sealed.ciphertext)
    }
}

// MARK: - Fakes for device-authn domain values

extension DeviceEnrollmentChallenge {
    static func fake(identityID: String = "identity-1") -> DeviceEnrollmentChallenge {
        DeviceEnrollmentChallenge(
            submitURL: URL(string: "https://ory.test/settings")!,
            nonce: Data("nonce".utf8),
            identityID: identityID
        )
    }
}

extension DeviceLoginChallenge {
    static func fake() -> DeviceLoginChallenge {
        DeviceLoginChallenge(submitURL: URL(string: "https://ory.test/login")!, nonce: Data("nonce".utf8))
    }
}

extension DeviceLoginOutcome {
    static func fake(token: String? = "ory_st_aal2") -> DeviceLoginOutcome {
        DeviceLoginOutcome(session: Sample.session(assuranceLevel: .aal2), token: token)
    }
}
