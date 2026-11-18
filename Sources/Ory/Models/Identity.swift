import Foundation

/// A user represented in Ory.
///
/// An identity's ``traits`` are defined by your project's identity schema, so their
/// shape is specific to your app. Rather than guess at a fixed structure, ``OryIdentity``
/// keeps the traits as raw JSON and lets you decode them into a `Decodable` type you
/// own:
///
/// ```swift
/// struct MyTraits: Decodable {
///     let email: String
///     let name: String?
/// }
///
/// let session = try await client.currentSession()
/// if let identity = session.identity {
///     let traits = try identity.decodeTraits(as: MyTraits.self)
///     print(traits.email)
/// }
/// ```
public struct OryIdentity: Sendable, Hashable {

    /// The identity's unique, immutable identifier.
    public let id: String

    /// The ID of the identity schema that defines and validates ``traits``.
    public let schemaID: String

    /// The identity's traits, as raw JSON. Decode with ``decodeTraits(as:)``.
    private let traitsJSON: Data

    /// Creates an identity.
    ///
    /// - Parameters:
    ///   - id: The identity's unique identifier.
    ///   - schemaID: The ID of the identity schema for ``traits``.
    ///   - traitsJSON: The identity's traits as raw JSON. Defaults to an empty object.
    public init(id: String, schemaID: String, traitsJSON: Data = Data("{}".utf8)) {
        self.id = id
        self.schemaID = schemaID
        self.traitsJSON = traitsJSON
    }

    /// Decodes the identity's traits into a type you define.
    ///
    /// Dates are decoded using the ISO 8601 strategy Ory uses on the wire.
    ///
    /// - Parameter type: The `Decodable` type matching your identity schema.
    /// - Returns: The decoded traits.
    /// - Throws: A `DecodingError` if the traits do not match `type`.
    public func decodeTraits<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try JSONDecoder.iso8601Decoder.decode(type, from: traitsJSON)
    }
}
