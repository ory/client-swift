/// A JSON value Ory returned without a fixed shape, such as the values in
/// ``OryUIMessage/context``.
///
/// Read it with pattern matching:
///
/// ```swift
/// if case let .int(minimum)? = message.context["min_length"] {
///     print("At least \(minimum) characters")
/// }
/// ```
///
/// A whole number decodes as ``int(_:)`` and any other number as ``double(_:)``.
public enum OryJSONValue: Sendable, Hashable {

    /// A string.
    case string(String)

    /// A whole number.
    case int(Int)

    /// A number with a fractional part, or one too large for `Int`.
    case double(Double)

    /// A boolean.
    case bool(Bool)

    /// An array.
    case array([OryJSONValue])

    /// An object, keyed by property name.
    case object([String: OryJSONValue])

    /// JSON `null`.
    case null
}
