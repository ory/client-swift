import Foundation

/// The kind of self-service flow.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryFlowKind: String, Sendable, Hashable {
    case login
    case registration
    case recovery
    case verification
    case settings
}

/// A server-driven flow you render and submit.
///
/// Ory decides which fields to show — a password form, a one-time code, a social
/// sign-in button, and so on — and returns them as ``nodes``. Render the visible
/// nodes, collect input, then submit. Hidden fields (CSRF tokens, nonces, internal
/// state) are carried for you automatically; you never handle them.
///
/// ```swift
/// let flow = try await client.createLoginFlow()
///
/// // Build your UI from the nodes the server returned.
/// for node in flow.nodes {
///     switch node.content {
///     case let .input(field) where field.kind == .password:
///         // render a secure text field bound to field.name
///     case let .input(field):
///         // render a text field bound to field.name
///     case let .text(text):
///         // render an informational label
///     default:
///         // images, links, and node kinds added in later releases
///         break
///     }
/// }
///
/// // Submit the values the user entered, pressing one of `flow.actions`.
/// var values = flow.makeValues()
/// values[.identifier] = email
/// values[.password] = password
///
/// let result = try await client.submitLoginFlow(
///     flow,
///     values: values,
///     pressing: flow.actions.first { $0.value == "password" }!
/// )
/// ```
public struct OryFlow: Sendable, Identifiable {

    /// The flow's unique identifier.
    public let id: String

    /// Which kind of flow this is.
    public let kind: OryFlowKind

    /// When the flow expires, if the server provided an expiry. Create a new flow after
    /// this time.
    public let expiresAt: Date?

    /// Form-level messages, such as "The login failed because…". Show these to the user.
    public let messages: [OryUIMessage]

    /// The renderable nodes, in display order. Hidden inputs are not included here —
    /// they are submitted for you automatically.
    public let nodes: [OryNode]

    /// The submit buttons the user can press, such as "Sign in" or "Continue with
    /// Google". Pass the pressed one to `submit…`.
    public let actions: [OryInputField]

    /// The assurance level a login flow must reach: ``OryAuthenticatorAssuranceLevel/aal2`` for
    /// a second-factor login, `nil` for other flow kinds.
    public let requestedAAL: OryAuthenticatorAssuranceLevel?

    /// Whether a login flow re-authenticates the signed-in user, as started with
    /// `OryLoginFlowOptions(refresh: true)`. Always `false` for other flow kinds.
    ///
    /// Use it with ``requestedAAL`` to title the screen, for example "Confirm it's you" instead
    /// of "Sign in".
    public let isRefresh: Bool

    /// Carries everything needed to submit: the action URL, method, and the hidden
    /// and default field values. Not exposed to integrators.
    let submission: OrySubmission

    /// Internal initializer used by the mappers, with full submission data.
    init(
        id: String,
        kind: OryFlowKind,
        expiresAt: Date?,
        messages: [OryUIMessage],
        nodes: [OryNode],
        actions: [OryInputField],
        requestedAAL: OryAuthenticatorAssuranceLevel? = nil,
        isRefresh: Bool = false,
        submission: OrySubmission
    ) {
        self.id = id
        self.kind = kind
        self.expiresAt = expiresAt
        self.messages = messages
        self.nodes = nodes
        self.actions = actions
        self.requestedAAL = requestedAAL
        self.isRefresh = isRefresh
        self.submission = submission
    }

    /// Creates a flow for tests and previews.
    ///
    /// Flows are normally produced by the client; this initializer lets you build one
    /// to drive UI in tests. A flow built this way cannot be submitted against a real
    /// server.
    public init(
        id: String,
        kind: OryFlowKind,
        expiresAt: Date? = nil,
        messages: [OryUIMessage] = [],
        nodes: [OryNode] = [],
        actions: [OryInputField] = [],
        requestedAAL: OryAuthenticatorAssuranceLevel? = nil,
        isRefresh: Bool = false
    ) {
        self.init(
            id: id,
            kind: kind,
            expiresAt: expiresAt,
            messages: messages,
            nodes: nodes,
            actions: actions,
            requestedAAL: requestedAAL,
            isRefresh: isRefresh,
            submission: .placeholder
        )
    }

    /// The authentication methods the user can choose between, in the order the server lists
    /// them — for example `[.password, .code]` for a login that offers a password and a
    /// one-time code.
    ///
    /// Each entry is the group of at least one action. Groups that only carry shared or
    /// step-navigation fields (``OryNodeGroup/default``, ``OryNodeGroup/identifierFirst``,
    /// ``OryNodeGroup/captcha``) are left out, and so is ``OryNodeGroup/profile`` except in a
    /// settings flow, where it is the profile section. Offer a method
    /// picker when there is more than one, then render every node and action that does not
    /// belong to another method. That keeps the shared and step-navigation ones, such as the
    /// identifier field and the Continue button of an identifier-first step, which belong to no
    /// method:
    ///
    /// ```swift
    /// let methods = flow.availableMethods
    /// let method = methods.first
    /// let isShown = { (group: OryNodeGroup) in !methods.contains(group) || group == method }
    /// let fields = flow.nodes.filter { isShown($0.group) }
    /// let buttons = flow.actions.filter { isShown($0.group) }
    /// ```
    ///
    /// ``OryNodeGroup/deviceAuthn`` is listed when the project offers device authentication.
    /// It needs a signature from this device, so use ``OryDeviceLogin/loginWithDevice(pin:)`` or
    /// ``OryDeviceStepUp/authenticateWithDevice(pin:)`` for it instead of submitting its action.
    public var availableMethods: [OryNodeGroup] {
        var methods: [OryNodeGroup] = []
        var shared: Set<OryNodeGroup> = [.default, .identifierFirst, .captcha]
        if kind != .settings {
            shared.insert(.profile)
        }
        for action in actions where !shared.contains(action.group) && !methods.contains(action.group) {
            methods.append(action.group)
        }
        return methods
    }

    /// The button that returns to the previous step of a two-step registration, where the user
    /// can change their profile details.
    ///
    /// Two-step registration first collects the profile (the identity traits) with the
    /// ``OryNodeGroup/profile`` action, then offers the credential methods in
    /// ``availableMethods``. On that second step, press this action with ``makeValues()`` to go
    /// back. `nil` on the first step and in other flows.
    ///
    /// Identifier-first login has no such button: the identifier step is followed by the
    /// methods for that account. To let the user change the identifier, start a new login flow.
    public var previousStepAction: OryInputField? {
        actions.first { $0.name == .screen && $0.value == "previous" }
    }

    /// The button that sends a new one-time code, once the flow has sent one.
    ///
    /// Show it next to the code field as "Resend code". Press it with ``makeValues()`` and
    /// without the code the user typed; the server sends a new code and returns
    /// ``OryFlowResult/pending(_:)`` with the same step:
    ///
    /// ```swift
    /// if let resend = flow.resendCodeAction {
    ///     let result = try await client.submitLoginFlow(flow, values: flow.makeValues(), pressing: resend)
    /// }
    /// ```
    ///
    /// The step after sending a code carries a message saying so — message id 1010014 on login,
    /// 1040005 on registration, 1060003 on recovery, and 1080003 on verification.
    ///
    /// `nil` before a code was sent and in flows without one-time codes.
    public var resendCodeAction: OryInputField? {
        actions.first { $0.group == .code && ($0.name == .resend || $0.name == .email) }
    }

    /// The QR code and secret for linking an authenticator app, in a settings flow that offers
    /// it. `nil` when TOTP is not enabled for the project, or already linked — then
    /// ``totpUnlinkAction`` is set instead.
    public var totpSetup: OryTOTPSetup? {
        var qrCode: Data?
        var secret: String?
        for node in nodes(in: .totp) {
            switch node.content {
            case let .image(url) where node.id == "totp_qr":
                qrCode = Self.dataURLContents(url)
            case let .text(text) where node.id == "totp_secret_key":
                secret = text
            default:
                break
            }
        }
        guard let qrCode, let secret else { return nil }
        return OryTOTPSetup(qrCodePNG: qrCode, secret: secret)
    }

    /// The settings button that unlinks the authenticator app, when one is linked. Press it with
    /// ``makeValues()``. Unlinking is a privileged change, like linking.
    public var totpUnlinkAction: OryInputField? {
        actions.first { $0.group == .totp && $0.name == .totpUnlink }
    }

    /// Decodes a base64 `data:` URL, which is how Ory embeds the TOTP QR code.
    private static func dataURLContents(_ url: URL) -> Data? {
        let string = url.absoluteString
        guard string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        guard string[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(string[string.index(after: comma)...]))
    }

    /// The visible nodes of one method, in server order.
    ///
    /// - Parameter group: The method, for example from ``availableMethods``.
    /// - Returns: The nodes whose ``OryNode/group`` is `group`.
    public func nodes(in group: OryNodeGroup) -> [OryNode] {
        nodes.filter { $0.group == group }
    }

    /// The actions of one method, in server order.
    ///
    /// - Parameter group: The method, for example from ``availableMethods``.
    /// - Returns: The actions whose ``OryInputField/group`` is `group`.
    public func actions(in group: OryNodeGroup) -> [OryInputField] {
        actions.filter { $0.group == group }
    }

    /// Builds the merged submission body: hidden and default values, overridden by the
    /// user's `values`, with the pressed action's `name=value` applied last.
    ///
    /// Email and identifier values are trimmed of surrounding whitespace, so a stray space or
    /// newline pasted with an address does not turn into an avoidable server-side error.
    func makeBody(
        values: OryFormValues,
        pressing action: OryInputField
    ) -> (url: URL, fields: [String: String]) {
        let emailLikeNames = Set(
            nodes.compactMap { node -> String? in
                guard case let .input(field) = node.content, field.isEmailLike else { return nil }
                return field.name.rawValue
            }
        )

        var fields = submission.values
        for (name, value) in values.wireValues() {
            fields[name] = emailLikeNames.contains(name)
                ? value.trimmingCharacters(in: .whitespacesAndNewlines)
                : value
        }
        fields[action.name.rawValue] = action.value ?? ""
        return (submission.action, fields)
    }
}

/// Everything needed to submit a flow, kept internal so integrators only deal with
/// visible fields.
struct OrySubmission: Sendable {

    /// The absolute URL to POST the merged form to.
    let action: URL

    /// The HTTP method (always `POST` for Ory flows).
    let method: String

    /// Hidden and default field values, keyed by field name. Excludes submit buttons.
    let values: [String: String]

    /// Whether the flow belongs to an existing session — a re-authentication or a
    /// second-factor login — and is therefore submitted with the session token.
    var sendsSessionToken = false

    /// A non-submittable placeholder used by flows built for tests.
    static let placeholder = OrySubmission(
        action: URL(string: "about:blank")!,
        method: "POST",
        values: [:]
    )
}
