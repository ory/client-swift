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
/// Hidden fields are not part of this — the client carries them for you.
public struct OryFormValues: Sendable {

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
}
