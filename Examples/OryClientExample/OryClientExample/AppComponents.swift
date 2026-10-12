import OryClient
#if targetEnvironment(simulator)
import OryClientSimulator
#endif

/// The app's composition root: it builds the shared ``OryClient`` once and exposes it as
/// ``oryClient``, so any coordinator or view model can depend on the same configured client
/// via `AppComponents.oryClient` instead of threading it down from the app entry point.
enum AppComponents {

    #if DEBUG
    static let networkHistory = NetworkHistoryStore()
    #endif

    /// The shared client. Inject it where a coordinator or view model needs one, e.g.
    /// `AuthCoordinator(client: AppComponents.oryClient, …)`.
    static let oryClient: OryClientProtocol = OryClient(
        configuration: OryClientConfiguration(
            projectURL: AppConfiguration.projectURL,
            sessionStorage: sessionStorage,
            requestInterceptors: requestInterceptors,
            responseInterceptors: responseInterceptors,
            networkObserver: networkObserver,
            deviceKeyAuthenticator: deviceKeyAuthenticator
        )
    )

    /// In debug builds, capture every request into ``networkHistory`` for the developer menu.
    private static var requestInterceptors: [any OryRequestInterceptor] {
        #if DEBUG
        [LoggingRequestInterceptor(store: networkHistory)]
        #else
        []
        #endif
    }

    /// In debug builds, capture every response into ``networkHistory`` for the developer menu.
    private static var responseInterceptors: [any OryResponseInterceptor] {
        #if DEBUG
        [LoggingResponseInterceptor(store: networkHistory)]
        #else
        []
        #endif
    }

    /// Owned explicitly so the same store backs the client and any direct access the app needs.
    /// Defaults to the Keychain, so the user stays signed in across launches.
    static let sessionStorage: OrySessionStorage = OryKeychainSessionStorage()

    /// In debug builds, print every request and response and record transport failures into
    /// the in-app network log. A real app might forward network events to its own observer here.
    private static var networkObserver: (any OryNetworkObserver)? {
        #if DEBUG
        DebugNetworkObserver(store: networkHistory)
        #else
        nil
        #endif
    }

    /// Device authentication uses the Secure Enclave via App Attest on a real device. The
    /// Simulator has none, so a relaxed authenticator is injected there; the Simulator branch
    /// is compiled out of device builds.
    private static var deviceKeyAuthenticator: any OryDeviceKeyAuthenticator {
        #if targetEnvironment(simulator)
        RelaxedDeviceKeyAuthenticator()
        #else
        OryAppAttestKeyAuthenticator()
        #endif
    }
}
