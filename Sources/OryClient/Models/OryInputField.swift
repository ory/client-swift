import Foundation

/// An input the server asked for, with everything you need to render it.
///
/// Bind your UI control to ``name`` and send the user's entry back under that name in
/// `submit…(values:)`.
public struct OryInputField: Sendable, Hashable {

    /// The kind of control to render, named after the HTML input type Ory sends.
    ///
    /// A wrapper around the input type rather than an enum, because Ory adds input types over
    /// time. Compare against the constants, and keep a `default:` arm in a `switch` — render
    /// an unrecognized kind as a plain text field so the user can still respond.
    public struct Kind: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

        /// The input type as Ory sends it, for example `datetime-local`.
        public let rawValue: String

        /// Creates a kind from the input type Ory sends.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String { rawValue }

        /// A single-line text field.
        public static let text = Kind(rawValue: "text")

        /// An email address field.
        public static let email = Kind(rawValue: "email")

        /// A secure text field.
        public static let password = Kind(rawValue: "password")

        /// A numeric field.
        public static let number = Kind(rawValue: "number")

        /// A phone number field.
        public static let telephone = Kind(rawValue: "tel")

        /// A checkbox or toggle.
        public static let checkbox = Kind(rawValue: "checkbox")

        /// A value carried for submission but never shown.
        public static let hidden = Kind(rawValue: "hidden")

        /// A button that submits the flow.
        public static let submit = Kind(rawValue: "submit")

        /// A button that submits the flow with its own value.
        public static let button = Kind(rawValue: "button")

        /// A date picker.
        public static let date = Kind(rawValue: "date")

        /// A date and time picker.
        public static let datetimeLocal = Kind(rawValue: "datetime-local")

        /// A URL field.
        public static let url = Kind(rawValue: "url")

        /// Whether this field is a button the user presses to submit the flow.
        public var isSubmit: Bool { self == .submit || self == .button }
    }

    /// A hint for the keyboard and autofill, mapping to SwiftUI `textContentType`.
    ///
    /// A wrapper around the HTML `autocomplete` token rather than an enum, because Ory adds
    /// hints over time. Compare against the constants, and keep a `default:` arm in a
    /// `switch`.
    public struct Autocomplete: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

        /// The autocomplete token as Ory sends it, for example `one-time-code`.
        public let rawValue: String

        /// Creates a hint from the autocomplete token Ory sends.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String { rawValue }

        /// An email address.
        public static let email = Autocomplete(rawValue: "email")

        /// A phone number.
        public static let telephone = Autocomplete(rawValue: "tel")

        /// A URL.
        public static let url = Autocomplete(rawValue: "url")

        /// The user's existing password.
        public static let currentPassword = Autocomplete(rawValue: "current-password")

        /// A new password, which the system can offer to generate.
        public static let newPassword = Autocomplete(rawValue: "new-password")

        /// A one-time code, which the system can fill from a message.
        public static let oneTimeCode = Autocomplete(rawValue: "one-time-code")

        /// The account username or identifier.
        public static let username = Autocomplete(rawValue: "username")

        /// The account username, which the system can also offer to fill with a passkey.
        public static let usernameWebAuthn = Autocomplete(rawValue: "username webauthn")
    }

    /// A selectable option for choice inputs.
    public struct Option: Sendable, Hashable {
        public let value: String
        public init(value: String) { self.value = value }
    }

    /// The typed field name. Use it as the key when submitting the user's value.
    public let name: OryFieldName

    /// The kind of control to render.
    public let kind: Kind

    /// A localized label to show with the control, if the server provided one.
    public let label: String?

    /// A prefilled value from the server. For buttons, the value submitted when pressed.
    public let value: String?

    /// Whether the user must provide a value.
    public let isRequired: Bool

    /// Whether the control should be shown disabled.
    public let isDisabled: Bool

    /// An autofill hint, if any.
    public let autocomplete: Autocomplete?

    /// Options for choice inputs; empty for plain inputs.
    public let options: [Option]

    /// The authentication method the field belongs to, such as ``OryNodeGroup/password`` or
    /// ``OryNodeGroup/code``.
    ///
    /// For an action it tells which method the button submits, so a screen can offer one
    /// method at a time. See ``OryFlow/availableMethods``.
    public let group: OryNodeGroup

    /// Creates an input field. Provided for tests and previews.
    public init(
        name: OryFieldName,
        kind: Kind,
        label: String? = nil,
        value: String? = nil,
        isRequired: Bool = false,
        isDisabled: Bool = false,
        autocomplete: Autocomplete? = nil,
        options: [Option] = [],
        group: OryNodeGroup = .default
    ) {
        self.name = name
        self.kind = kind
        self.label = label
        self.value = value
        self.isRequired = isRequired
        self.isDisabled = isDisabled
        self.autocomplete = autocomplete
        self.options = options
        self.group = group
    }

    /// Whether this field holds an email address or account identifier, whose value the
    /// client trims of surrounding whitespace before submitting. A login `identifier` is a
    /// plain text input on the wire, so it is matched by name; schema email traits are matched
    /// by their `email` kind.
    var isEmailLike: Bool {
        kind == .email || name == .identifier
    }
}
