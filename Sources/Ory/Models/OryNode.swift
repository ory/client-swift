import Foundation

/// Which authentication method a node belongs to.
///
/// Use this to group or style nodes — for example to render all `oidc` buttons
/// together, or to give the `password` group its own section.
///
/// It is a wrapper around the server's group name rather than an enum, because Ory adds
/// methods over time. Compare against the constants below, and always keep a `default:` arm
/// when you `switch` over it — the compiler requires one:
///
/// ```swift
/// switch node.group {
/// case .password:
///     passwordSection.append(node)
/// case .oidc:
///     socialButtons.append(node)
/// default:
///     otherSection.append(node)
/// }
/// ```
public struct OryNodeGroup: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

    /// The group name as Ory sends it, for example `lookup_secret`.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public extension OryNodeGroup {
    /// Fields shared by every method, such as the identifier or hidden state.
    static let `default` = OryNodeGroup(rawValue: "default")

    /// Password sign-in, registration, and password changes.
    static let password = OryNodeGroup(rawValue: "password")

    /// Social sign-in and OpenID Connect providers. Submitting one throws
    /// ``OryClientError/browserLocationChangeRequired(redirectURL:)``, which OryClient does not
    /// complete: hide the actions in this group.
    static let oidc = OryNodeGroup(rawValue: "oidc")

    /// Identity traits, such as the name or email address.
    static let profile = OryNodeGroup(rawValue: "profile")

    /// Recovery and verification by magic link. OryClient cannot complete this method: hide the actions in this group.
    static let link = OryNodeGroup(rawValue: "link")

    /// One-time codes for sign-in, registration, recovery, and verification.
    static let code = OryNodeGroup(rawValue: "code")

    /// Authenticator-app one-time passwords.
    static let totp = OryNodeGroup(rawValue: "totp")

    /// Backup recovery codes. OryClient cannot complete this method: hide the actions in this group.
    static let lookupSecret = OryNodeGroup(rawValue: "lookup_secret")

    /// Security keys and platform authenticators used as a second factor. OryClient cannot complete this method: hide the actions in this group.
    static let webauthn = OryNodeGroup(rawValue: "webauthn")

    /// Passkeys. OryClient cannot complete this method: hide the actions in this group.
    static let passkey = OryNodeGroup(rawValue: "passkey")

    /// The identifier step of a two-step sign-in.
    static let identifierFirst = OryNodeGroup(rawValue: "identifier_first")

    /// A captcha challenge. OryClient cannot complete this method: hide the actions in this group.
    static let captcha = OryNodeGroup(rawValue: "captcha")

    /// SAML single sign-on. OryClient cannot complete this method: hide the actions in this group.
    static let saml = OryNodeGroup(rawValue: "saml")

    /// Device authentication with this device's key.
    static let deviceAuthn = OryNodeGroup(rawValue: "deviceauthn")

    /// OAuth2 consent. OryClient cannot complete this method: hide the actions in this group.
    static let oauth2Consent = OryNodeGroup(rawValue: "oauth2_consent")
}

/// A single renderable element of a flow.
public struct OryNode: Sendable, Hashable, Identifiable {

    /// A stable identifier for the node, suitable as a SwiftUI `id`.
    public let id: String

    /// The authentication method this node belongs to.
    public let group: OryNodeGroup

    /// Validation or hint messages attached to this node. Show these next to the field.
    public let messages: [OryUIMessage]

    /// What to render for this node.
    public let content: OryNodeContent

    /// Creates a node. Provided for tests and previews.
    public init(id: String, group: OryNodeGroup, messages: [OryUIMessage] = [], content: OryNodeContent) {
        self.id = id
        self.group = group
        self.messages = messages
        self.content = content
    }

    /// The input the user fills in, when this node is one; `nil` for text, images and links.
    ///
    /// Use it to read a node's field without matching on ``content``:
    ///
    /// ```swift
    /// for node in flow.nodes {
    ///     if let field = node.inputField {
    ///         // Render a text or secure field bound to values[field].
    ///     }
    /// }
    ///
    /// let identifier = flow.nodes.lazy.compactMap(\.inputField).first { $0.name == .identifier }
    /// ```
    public var inputField: OryInputField? {
        guard case let .input(field) = content else { return nil }
        return field
    }
}

/// What a node renders as.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryNodeContent: Sendable, Hashable {

    /// An input the user fills in (text, password, checkbox, a submit button, …).
    case input(OryInputField)

    /// Informational text to display, such as the secret of an authenticator app. Show
    /// ``OryUIMessage/text``, or translate it from its ``OryUIMessage/id`` and
    /// ``OryUIMessage/context``.
    case text(OryUIMessage)

    /// An image to display, such as a QR code.
    case image(url: URL)

    /// A link the user can follow, such as "Continue" after a verification. Show the label's
    /// ``OryUIMessage/text``.
    case link(label: OryUIMessage, url: URL)
}
