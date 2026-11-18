import Foundation

/// A ``FrontendRequest`` reduced to what the transport needs to build a `URLRequest`:
/// the method, absolute URL, encoded body, and session token (if any). Header
/// application and interceptors are the transport's concern, not this value's.
struct ResolvedHTTPRequest: Sendable {
    let method: HTTPMethod
    let url: URL
    let body: Data?
    let sessionToken: String?
}

/// Turns a typed ``FrontendRequest`` into a ``ResolvedHTTPRequest``. Kept separate from
/// the transport so both the live client and test doubles resolve requests identically.
enum FrontendRequestResolver {

    static func resolve<R: FrontendRequest>(_ request: R, baseURL: URL) throws -> ResolvedHTTPRequest {
        let sessionToken: String?
        switch request.authorization {
        case .none:
            sessionToken = nil
        case let .sessionToken(token):
            sessionToken = token
        }
        return ResolvedHTTPRequest(
            method: request.method,
            url: url(for: request.target, baseURL: baseURL),
            body: try encode(request.body),
            sessionToken: sessionToken
        )
    }

    static func url(for target: RequestTarget, baseURL: URL) -> URL {
        switch target {
        case let .url(url):
            return url
        case let .path(path, query):
            var base = baseURL.absoluteString
            if base.hasSuffix("/") {
                base.removeLast()
            }
            guard var components = URLComponents(string: base + path) else {
                return baseURL
            }
            if !query.isEmpty {
                components.queryItems = query
            }
            return components.url ?? baseURL
        }
    }

    /// Encodes a body. `Data` fields serialize as base64, matching the SDK's wire format
    /// (only the decoder customizes the date strategy; request bodies carry no dates).
    private static func encode(_ body: (any Encodable & Sendable)?) throws -> Data? {
        guard let body else { return nil }
        do {
            return try JSONEncoder().encode(AnyEncodable(body))
        } catch {
            throw OryClientError.unexpectedResponse(underlying: UnderlyingError(error))
        }
    }
}

/// Erases an `any Encodable` so `JSONEncoder` can encode it without a concrete type.
private struct AnyEncodable: Encodable {
    private let encodeTo: (any Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeTo = wrapped.encode }
    func encode(to encoder: any Encoder) throws { try encodeTo(encoder) }
}
