import Foundation

/// A raw response from the transport: the decoded status and body bytes, plus typed
/// decoding helpers. The transport stays free of any API or SDK semantics; the
/// repository decides which DTO to decode for which status.
struct HTTPResponse<Success: Decodable & Sendable>: Sendable {

    let status: Int
    let data: Data
    /// Response headers, keyed by their canonical (lowercased) name — `Retry-After` on a rate
    /// limit is the one the client acts on.
    let headers: [String: String]

    init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }

    /// Decodes the request's declared 2xx ``FrontendRequest/Response``.
    func success() throws -> Success {
        try decode(Success.self)
    }

    /// Decodes an arbitrary DTO from the body — for the `400` flow a submit re-renders,
    /// or an error body. Failures surface as ``OryClientError/unexpectedResponse(underlying:)``.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        // A zero-byte body is invalid JSON; treat it as `null` so an empty 2xx response
        // (e.g. native logout) decodes into ``OryEmptyResponse``.
        let bytes = data.isEmpty ? Data("null".utf8) : data
        do {
            return try OryDecoder.shared.decode(type, from: bytes)
        } catch {
            throw OryClientError.unexpectedResponse(underlying: UnderlyingError(error))
        }
    }
}

/// The ``FrontendRequest/Response`` for endpoints that return no body on success, such as
/// native logout. Decodes from an empty (or `null`) body and carries nothing.
struct OryEmptyResponse: Decodable, Sendable {

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an empty response body.")
        }
    }
}
