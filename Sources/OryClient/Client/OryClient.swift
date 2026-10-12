import Foundation

/// The entry point for integrating Ory into your iOS app.
///
/// Create one instance, typically at app start, and share it:
///
/// ```swift
/// let client = OryClient(
///     configuration: OryClientConfiguration(
///         projectURL: URL(string: "https://your-slug.projects.oryapis.com")!
///     )
/// )
///
/// let session = try await client.currentSession()
/// ```
///
/// Persistent state lives in the injected session and device key stores. Device
/// enrollment, PIN rotation, removal, forgetting and key-based authentication are
/// mutually exclusive across clients sharing a ``OryDeviceKeyStore/deviceOperationScope``
/// in this process. Overlapping calls throw
/// ``OryClientError/deviceAuthenticationOperationInProgress`` before starting work.
/// Read-only enrollment checks and device listings return snapshots.
///
/// The per-flow methods live in the `OryClient+*` extension files (`+Login`,
/// `+Registration`, `+Verification`, `+DeviceAuthn`); this file holds construction,
/// session lookup, and the helpers shared across them.
public final class OryClient: Sendable {

    let storage: OrySessionStorage
    let session: any SessionRepository
    let login: any LoginRepository
    let registration: any RegistrationRepository
    let verification: any VerificationRepository
    let recovery: any RecoveryRepository
    let settings: any SettingsRepository
    let deviceAuthn: any DeviceAuthnRepository
    let deviceKeyStore: OryDeviceKeyStore
    let deviceAuthenticator: OryDeviceKeyAuthenticator
    let biometricAuthenticator: OryBiometricAuthenticator
    let biometricSignInReason: String
    let biometricEnrollReason: String
    let pinVault: DevicePINVault

    /// Creates a client from a configuration.
    ///
    /// - Parameter configuration: The project URL and storage to use.
    public convenience init(configuration: OryClientConfiguration) {
        let client = URLSessionHTTPClient(
            baseURL: configuration.projectURL,
            transport: configuration.transport,
            requestInterceptors: configuration.requestInterceptors,
            responseInterceptors: configuration.responseInterceptors,
            observer: configuration.networkObserver
        )
        let gateway = FrontendGateway(client: client)
        self.init(
            storage: configuration.sessionStorage,
            frontend: LiveFrontendRepository(gateway: gateway),
            deviceAuthn: LiveDeviceAuthnRepository(gateway: gateway),
            deviceKeyStore: configuration.deviceKeyStore,
            deviceAuthenticator: configuration.deviceKeyAuthenticator,
            biometricAuthenticator: configuration.biometricAuthenticator,
            biometricSignInReason: configuration.biometricSignInReason,
            biometricEnrollReason: configuration.biometricEnrollReason,
            pinSealingKeyProvider: configuration.pinSealingKeyProvider
        )
    }

    /// Internal designated initializer used to inject fakes in tests. The device-authn
    /// dependencies default to their production implementations.
    init(
        storage: OrySessionStorage,
        frontend: any SessionRepository & LoginRepository & RegistrationRepository & VerificationRepository & RecoveryRepository & SettingsRepository,
        deviceAuthn: any DeviceAuthnRepository,
        deviceKeyStore: OryDeviceKeyStore = OryKeychainDeviceKeyStore(),
        deviceAuthenticator: OryDeviceKeyAuthenticator = OryAppAttestKeyAuthenticator(),
        biometricAuthenticator: OryBiometricAuthenticator = OryLocalAuthenticationBiometricAuthenticator(),
        biometricSignInReason: String = OryClientConfiguration.defaultBiometricSignInReason,
        biometricEnrollReason: String = OryClientConfiguration.defaultBiometricEnrollReason,
        pinSealingKeyProvider: any OryPINSealingKeyProvider = OrySecureEnclavePINSealingKeyProvider()
    ) {
        self.storage = storage
        self.session = frontend
        self.login = frontend
        self.registration = frontend
        self.verification = frontend
        self.recovery = frontend
        self.settings = frontend
        self.deviceAuthn = deviceAuthn
        self.deviceKeyStore = deviceKeyStore
        self.deviceAuthenticator = deviceAuthenticator
        self.biometricAuthenticator = biometricAuthenticator
        self.biometricSignInReason = biometricSignInReason
        self.biometricEnrollReason = biometricEnrollReason
        self.pinVault = DevicePINVault(sealingKeyProvider: pinSealingKeyProvider)
    }

    // MARK: - Shared helpers (used by the OryClient+* extensions)

    /// Returns the stored session token, or throws ``OryClientError/notAuthenticated``
    /// when none is stored, mapping storage failures into ``OryClientError``.
    func requireSessionToken() async throws -> String {
        let token: String?
        do {
            token = try await storage.sessionToken()
        } catch {
            throw Self.storageError(error)
        }
        guard let token, !token.isEmpty else {
            throw OryClientError.notAuthenticated
        }
        return token
    }

    /// Stores a session token, mapping storage failures into ``OryClientError``.
    func storeToken(_ token: String) async throws {
        do {
            try await storage.store(sessionToken: token)
        } catch {
            throw Self.storageError(error)
        }
    }

    /// Wraps a ``OrySessionStorage`` failure into ``OryClientError``, preserving a
    /// `Sendable` cause.
    static func storageError(_ error: any Error) -> OryClientError {
        if let ory = error as? OryClientError {
            return ory
        }
        if let keychain = error as? OryKeychainError {
            return .storage(underlying: keychain)
        }
        return .storage(underlying: UnderlyingError(error))
    }
}

/// ``OryClient`` satisfies ``OryClientProtocol`` through the per-concern conformances
/// declared in the `OryClient+*` extension files (``OrySessionManagement``, ``OryLoginFlow``,
/// the `OryDevice*` protocols, …).
extension OryClient: OryClientProtocol {}
