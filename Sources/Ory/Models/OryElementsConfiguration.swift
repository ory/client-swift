import Foundation

/// The project settings that decide how sign-in screens look and which flows they offer.
///
/// Returned by ``OryElementsConfigurationLoading/elementsConfiguration()``. It is the same
/// document web Ory Elements reads, and you edit it in the Ory Console. Because the project
/// can change at any time, load it again with every flow you show instead of keeping it. A
/// self-hosted Kratos has no Ory Elements configuration, so treat it as optional:
///
/// ```swift
/// async let configuration = try? client.elementsConfiguration()
/// let flow = try await client.createLoginFlow()
///
/// let screen = await LoginScreen(flow: flow, configuration: configuration)
/// ```
///
/// The configuration's web addresses for hosted pages and its default redirect are left out,
/// because a native app navigates on its own. Which device keys may sign in without a password
/// comes with each login flow instead, as ``OryFlow/firstFactorDeviceMethods``.
public struct OryElementsConfiguration: Sendable, Hashable {

    /// The project's name, shown on the sign-in card when there is no logo.
    public var name: String

    /// The logo for light appearance, or `nil` when none is set.
    public var logoLightURL: URL?

    /// The logo for dark appearance, or `nil` when none is set. Fall back to
    /// ``logoLightURL`` when it is `nil`.
    public var logoDarkURL: URL?

    /// Whether the project allows registration.
    ///
    /// When `false`, the server rejects new registration flows, so do not offer a way to sign up.
    public var registrationEnabled: Bool

    /// Whether to hide the sign-up link on the sign-in screen, even though registration is allowed.
    public var hideRegistrationLink: Bool

    /// Whether the project allows email or phone verification.
    public var verificationEnabled: Bool

    /// Whether the project allows account recovery. When `false`, do not offer "Forgot password".
    public var recoveryEnabled: Bool

    /// The project's terms of service, or `nil` when none is set.
    public var termsOfServiceURL: URL?

    /// The project's privacy policy, or `nil` when none is set.
    public var privacyPolicyURL: URL?

    /// The project's contact page or address, for example a `mailto:` URL, or `nil` when none is set.
    public var contactURL: URL?

    /// Whether to hide the Ory badge on the sign-in card.
    public var hideOryBranding: Bool

    /// Creates a configuration, for example for SwiftUI previews and tests.
    ///
    /// The defaults match a project that has changed none of these settings.
    ///
    /// - Parameters:
    ///   - name: The project's name.
    ///   - logoLightURL: The logo for light appearance.
    ///   - logoDarkURL: The logo for dark appearance.
    ///   - registrationEnabled: Whether the project allows registration.
    ///   - hideRegistrationLink: Whether to hide the sign-up link on the sign-in screen.
    ///   - verificationEnabled: Whether the project allows verification.
    ///   - recoveryEnabled: Whether the project allows account recovery.
    ///   - termsOfServiceURL: The project's terms of service.
    ///   - privacyPolicyURL: The project's privacy policy.
    ///   - contactURL: The project's contact page or address.
    ///   - hideOryBranding: Whether to hide the Ory badge.
    public init(
        name: String,
        logoLightURL: URL? = nil,
        logoDarkURL: URL? = nil,
        registrationEnabled: Bool = true,
        hideRegistrationLink: Bool = false,
        verificationEnabled: Bool = true,
        recoveryEnabled: Bool = true,
        termsOfServiceURL: URL? = nil,
        privacyPolicyURL: URL? = nil,
        contactURL: URL? = nil,
        hideOryBranding: Bool = false
    ) {
        self.name = name
        self.logoLightURL = logoLightURL
        self.logoDarkURL = logoDarkURL
        self.registrationEnabled = registrationEnabled
        self.hideRegistrationLink = hideRegistrationLink
        self.verificationEnabled = verificationEnabled
        self.recoveryEnabled = recoveryEnabled
        self.termsOfServiceURL = termsOfServiceURL
        self.privacyPolicyURL = privacyPolicyURL
        self.contactURL = contactURL
        self.hideOryBranding = hideOryBranding
    }
}
