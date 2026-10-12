import Foundation

/// A typed name for a flow input field.
///
/// The well-known authentication fields have constants, so you can reference them in a
/// type-safe, autocomplete-friendly way. Identity-schema traits and fields added by a newer
/// backend use the name Ory sends:
///
/// ```swift
/// switch field.name {
/// case .identifier: // username field
/// case .password:   // password field
/// case OryFieldName(rawValue: "traits.email"): // a schema trait
/// default: break
/// }
/// ```
///
/// It is a wrapper around the field name rather than an enum, because Ory adds fields over
/// time. Two names are equal when their ``rawValue`` is equal, so a name you build from a
/// string keeps matching after a later release adds a constant for it.
public struct OryFieldName: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

    /// The field name sent to and from the server, for example `totp_code` or `traits.email`.
    public let rawValue: String

    /// Creates a field name from the name Ory sends.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public extension OryFieldName {

    /// The account identifier, such as an email address or username, on sign-in.
    static let identifier = OryFieldName(rawValue: "identifier")

    /// The password.
    static let password = OryFieldName(rawValue: "password")

    /// A one-time code sent by email or SMS.
    static let code = OryFieldName(rawValue: "code")

    /// An authenticator-app one-time password.
    static let totpCode = OryFieldName(rawValue: "totp_code")

    /// A backup recovery code.
    static let lookupSecret = OryFieldName(rawValue: "lookup_secret")

    /// The social sign-in provider to use.
    static let provider = OryFieldName(rawValue: "provider")

    /// The authentication method the submission is for. Set by pressing one of
    /// ``OryFlow/actions``.
    static let method = OryFieldName(rawValue: "method")

    /// The anti-CSRF token. Carried for you; you never set it.
    static let csrfToken = OryFieldName(rawValue: "csrf_token")
}
