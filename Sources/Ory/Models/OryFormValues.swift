import Foundation

/// A type-safe, prefilled bag of the values a user enters into a flow.
///
/// Get one prefilled from a flow with ``OryFlow/makeValues()``, then read and write
/// per field. The subscript always returns a value (never `nil`), so your binding code
/// stays clean — no empty-string fallbacks:
///
/// ```swift
/// var values = flow.makeValues()
/// values[passwordField] = "hunter2"      // by field
/// values[.identifier] = "alice@acme.com" // or by typed name
///
/// let result = try await client.submitLoginFlow(flow, values: values, pressing: action)
/// ```
///
/// When a submit returns the next step, fill its bag with ``OryFlow/makeValues(keeping:)`` to
/// keep what the user typed.
///
/// Hidden fields are not part of this — the client carries them for you.
public struct OryFormValues: Sendable, Hashable {

    /// Values keyed by wire field name.
    private var storage: [String: String]

    /// Creates an empty bag.
    public init() {
        storage = [:]
    }

    /// Creates a bag prefilled with the visible fields' server-provided defaults.
    init(seededFrom flow: OryFlow) {
        var seed: [String: String] = [:]
        for node in flow.nodes {
            if case let .input(field) = node.content {
                seed[field.name.rawValue] = field.value ?? ""
            }
        }
        storage = seed
    }

    /// Reads or writes a field's value. Always returns a value, defaulting to `""`.
    public subscript(_ field: OryInputField) -> String {
        get { storage[field.name.rawValue] ?? "" }
        set { storage[field.name.rawValue] = newValue }
    }

    /// Reads or writes a value by typed field name, for fields you reference directly.
    public subscript(_ name: OryFieldName) -> String {
        get { storage[name.rawValue] ?? "" }
        set { storage[name.rawValue] = newValue }
    }

    /// The values keyed by wire name, for building the submission body.
    func wireValues() -> [String: String] {
        storage
    }
}

public extension OryFlow {

    /// A bag of input values for this flow, prefilled with server-provided defaults.
    ///
    /// Bind your UI to the returned ``OryFormValues`` and pass it back to `submit…`.
    func makeValues() -> OryFormValues {
        OryFormValues(seededFrom: self)
    }

    /// A bag of input values for this flow that keeps what the user typed into an earlier one.
    ///
    /// Use it when a submit returns the next step as ``OryFlowResult/pending(_:)``, or when you
    /// replace an expired flow, so the user does not type the same entries again. The bag starts
    /// as ``makeValues()`` and takes each non-empty value from `previous` for an input this flow
    /// still has:
    ///
    /// - Passwords and one-time codes (an emailed or texted code, an authenticator-app code, a
    ///   backup code) are cleared, also when the server prefilled them, so the user enters
    ///   them again on the new step.
    /// - Values of inputs this flow no longer has are dropped, so they are not submitted.
    /// - Where the user left an input empty, the server's prefilled value stays.
    ///
    /// A kept value replaces the server's prefilled one, also when it was the earlier flow's
    /// prefilled value. To start from the server's values only, use ``makeValues()``.
    ///
    /// ```swift
    /// let result = try await client.submitLoginFlow(flow, values: values, pressing: action)
    /// if case let .pending(next) = result {
    ///     values = next.makeValues(keeping: values)
    ///     flow = next
    /// }
    /// ```
    ///
    /// - Parameter previous: The values the user entered into the earlier flow.
    /// - Returns: A bag for this flow with the user's entries kept, except passwords and
    ///   one-time codes.
    func makeValues(keeping previous: OryFormValues) -> OryFormValues {
        var values = makeValues()
        for field in nodes.compactMap(\.inputField) {
            if field.isEnteredOnEveryStep {
                values[field] = ""
            } else if !previous[field].isEmpty {
                values[field] = previous[field]
            }
        }
        return values
    }
}

private extension OryInputField {

    static let oneTimeCodeNames: Set<OryFieldName> = [.code, .totpCode, OryFieldName(rawValue: "lookup_secret")]

    var isEnteredOnEveryStep: Bool {
        kind == .password || autocomplete == .oneTimeCode || Self.oneTimeCodeNames.contains(name)
    }
}
