import Foundation

/// The configuration ``OryClient`` is created with.
///
/// ```swift
/// let config = OryClientConfiguration(
///     projectURL: URL(string: "https://your-slug.projects.oryapis.com")!
/// )
/// let client = OryClient(configuration: config)
/// ```
///
/// By default the session token and the enrolled device key are kept in the Keychain,
/// scoped to `projectURL`, so clients for different Ory projects in one app never share
/// them. To customize where the session token is stored — for example to share it with an
/// app extension — pass your own ``OrySessionStorage``:
///
/// ```swift
/// let config = OryClientConfiguration(
///     projectURL: projectURL,
///     sessionStorage: OryKeychainSessionStorage(projectURL: projectURL, accessGroup: "TEAMID.com.acme.shared")
/// )
/// ```
public struct OryClientConfiguration: Sendable {

    /// The base URL of your Ory project, for example
    /// `https://your-slug.projects.oryapis.com`.
    public let projectURL: URL

    /// Where the session token is persisted. Defaults to ``OryKeychainSessionStorage``
    /// scoped to ``projectURL``.
    public let sessionStorage: OrySessionStorage

    /// Where the enrolled device key is persisted. Defaults to ``OryKeychainDeviceKeyStore``
    /// scoped to ``projectURL``. Override to share the key with an app extension via a Keychain access group, or to
    /// keep tests isolated with `InMemoryDeviceKeyStore` from `OryTestDoubles`.
    public let deviceKeyStore: OryDeviceKeyStore

    /// The key that wraps PIN material at rest. Only `OryTestDoubles` changes it, through
    /// `usingInsecurePINSealingForTests()`.
    package var pinSealingKeyProvider: any OryPINSealingKeyProvider = OrySecureEnclavePINSealingKeyProvider()

    /// Hooks that add headers to every outgoing request (tracing, correlation IDs). Applied in
    /// order; for the common case use ``OryHeaderInterceptor``.
    public let requestInterceptors: [any OryRequestInterceptor]

    /// Hooks that inspect every response before it is decoded, for example for logging.
    /// Applied in order.
    public let responseInterceptors: [any OryResponseInterceptor]

    /// An optional hook to observe network activity (logging, metrics, Sentry).
    public let networkObserver: (any OryNetworkObserver)?

    /// Which `URLSession` API the client sends requests with. Only `OrySimulator`
    /// changes it, through `usingLegacyDataTaskTransport()`.
    package var transport: HTTPTransport = .automatic

    /// How device authentication signs and attests. Defaults to
    /// ``OryAppAttestKeyAuthenticator`` (the Secure Enclave). Override only for advanced
    /// scenarios — most notably to run on the Simulator with a relaxed implementation
    /// from the `OrySimulator` product, guarded by `#if targetEnvironment(simulator)`:
    ///
    /// ```swift
    /// let config: OryClientConfiguration = {
    ///     #if targetEnvironment(simulator)
    ///     return OryClientConfiguration(projectURL: url, deviceKeyAuthenticator: RelaxedDeviceKeyAuthenticator())
    ///     #else
    ///     return OryClientConfiguration(projectURL: url)
    ///     #endif
    /// }()
    /// ```
    public let deviceKeyAuthenticator: OryDeviceKeyAuthenticator

    /// How biometric verification (Face ID / Touch ID / Optic ID) is checked before signing
    /// with a biometric device key. Defaults to ``OryLocalAuthenticationBiometricAuthenticator``.
    /// Override only to unit-test biometric flows without a system prompt.
    public let biometricAuthenticator: OryBiometricAuthenticator

    /// The message shown in the biometric system prompt when signing in or stepping up with a
    /// biometric device key. Localize or brand it for your app.
    public let biometricSignInReason: String

    /// The message shown in the biometric system prompt when enrolling a biometric device key.
    /// Localize or brand it for your app.
    public let biometricEnrollReason: String

    /// The rule a PIN must follow before ``OryClient`` enrolls a device with it or sets it as
    /// the new PIN. Defaults to ``OryPINPolicy/default``.
    public let pinPolicy: OryPINPolicy

    /// The default ``biometricSignInReason``.
    public static let defaultBiometricSignInReason = "Confirm it's you to continue."

    /// The default ``biometricEnrollReason``.
    public static let defaultBiometricEnrollReason = "Confirm it's you to set up sign-in on this device."

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - projectURL: The base URL of your Ory project.
    ///   - sessionStorage: Where the session token is persisted. Defaults to `nil`, which
    ///     selects the system Keychain via ``OryKeychainSessionStorage/init(projectURL:accessGroup:)``
    ///     scoped to `projectURL`.
    ///   - deviceKeyStore: Where the enrolled device key is persisted. Defaults to `nil`, which
    ///     selects the system Keychain via ``OryKeychainDeviceKeyStore/init(projectURL:accessGroup:)``
    ///     scoped to `projectURL`.
    ///   - requestInterceptors: ``OryRequestInterceptor``s that add headers to outgoing
    ///     requests, applied in order. Defaults to none.
    ///   - responseInterceptors: ``OryResponseInterceptor``s that inspect responses,
    ///     applied in order. Defaults to none.
    ///   - networkObserver: An optional ``OryNetworkObserver`` to observe requests and
    ///     responses, for example ``OryConsoleNetworkObserver`` in debug builds.
    ///   - deviceKeyAuthenticator: How device authentication signs and attests. Defaults
    ///     to ``OryAppAttestKeyAuthenticator``. Override only on the Simulator.
    ///   - biometricAuthenticator: How biometric verification is performed before signing
    ///     with a biometric device key. Defaults to ``OryLocalAuthenticationBiometricAuthenticator``.
    ///   - biometricSignInReason: The localized biometric-prompt message for sign-in and
    ///     step-up. Defaults to ``defaultBiometricSignInReason``.
    ///   - biometricEnrollReason: The localized biometric-prompt message for enrollment.
    ///     Defaults to ``defaultBiometricEnrollReason``.
    ///   - pinPolicy: The rule a PIN must follow before it is enrolled or set as the new PIN.
    ///     Defaults to ``OryPINPolicy/default``. Your policy replaces the default entirely.
    public init(
        projectURL: URL,
        sessionStorage: OrySessionStorage? = nil,
        deviceKeyStore: OryDeviceKeyStore? = nil,
        requestInterceptors: [any OryRequestInterceptor] = [],
        responseInterceptors: [any OryResponseInterceptor] = [],
        networkObserver: (any OryNetworkObserver)? = nil,
        deviceKeyAuthenticator: OryDeviceKeyAuthenticator = OryAppAttestKeyAuthenticator(),
        biometricAuthenticator: OryBiometricAuthenticator = OryLocalAuthenticationBiometricAuthenticator(),
        biometricSignInReason: String = OryClientConfiguration.defaultBiometricSignInReason,
        biometricEnrollReason: String = OryClientConfiguration.defaultBiometricEnrollReason,
        pinPolicy: OryPINPolicy = .default
    ) {
        self.projectURL = projectURL
        self.sessionStorage = sessionStorage ?? OryKeychainSessionStorage(projectURL: projectURL)
        self.deviceKeyStore = deviceKeyStore ?? OryKeychainDeviceKeyStore(projectURL: projectURL)
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.networkObserver = networkObserver
        self.deviceKeyAuthenticator = deviceKeyAuthenticator
        self.biometricAuthenticator = biometricAuthenticator
        self.biometricSignInReason = biometricSignInReason
        self.biometricEnrollReason = biometricEnrollReason
        self.pinPolicy = pinPolicy
    }
}
