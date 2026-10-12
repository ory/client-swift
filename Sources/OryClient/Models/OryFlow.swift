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
        submission: OrySubmission
    ) {
        self.id = id
        self.kind = kind
        self.expiresAt = expiresAt
        self.messages = messages
        self.nodes = nodes
        self.actions = actions
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
        actions: [OryInputField] = []
    ) {
        self.init(
            id: id,
            kind: kind,
            expiresAt: expiresAt,
            messages: messages,
            nodes: nodes,
            actions: actions,
            submission: .placeholder
        )
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

    /// A non-submittable placeholder used by flows built for tests.
    static let placeholder = OrySubmission(
        action: URL(string: "about:blank")!,
        method: "POST",
        values: [:]
    )
}
