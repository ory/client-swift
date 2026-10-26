import Foundation

/// A request the client is about to send, exposed to a ``OryRequestInterceptor``. An
/// interceptor can change the headers; the method, URL, and body are read-only.
///
/// ``headers`` already contains `Accept`, `Content-Type` for a request with a body, and
/// `Ory-Client`, which tells Ory the client package, its version, and the OS — for example
/// `ory-client-swift/0.1.0 (iOS 18.2.0)`. It carries no user or device identifiers.
///
/// The session-token header is applied by the client *after* every interceptor runs, so
/// an interceptor cannot read or overwrite it here.
public struct OryOutgoingRequest: Sendable {

    /// The HTTP method, e.g. `GET` or `POST`.
    public let method: String

    /// The request URL.
    public let url: URL

    /// The request headers.
    public var headers: [String: String]

    /// A copy of the JSON request body with credential values — such as `password`, `code`,
    /// `pin_proof`, and `csrf_token` — replaced by `"[REDACTED]"`, so it is safe to log. The
    /// client sends the original body.
    public let body: Data?

    /// Creates a request, for example to unit-test your own interceptor.
    public init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// Adapts the client's outgoing requests.
///
/// Conform a type and pass it in ``OryClientConfiguration/requestInterceptors`` to attach
/// headers such as tracing or correlation IDs. Interceptors run in array order, each receiving
/// the previous one's output. Only the headers an interceptor returns affect the request.
///
/// ```swift
/// struct TracingInterceptor: OryRequestInterceptor {
///     func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest {
///         var request = request
///         request.headers["X-Trace-Id"] = UUID().uuidString
///         return request
///     }
/// }
/// ```
///
/// - Note: The session-token header is always applied by the client after the
///   interceptors, so it cannot be accidentally overwritten. For the common case of just
///   adding headers, use ``OryHeaderInterceptor``.
public protocol OryRequestInterceptor: Sendable {
    func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest
}

/// A ready-made ``OryRequestInterceptor`` that adds headers, computed per request URL.
///
/// ```swift
/// let config = OryClientConfiguration(
///     projectURL: projectURL,
///     requestInterceptors: [OryHeaderInterceptor { _ in ["X-Trace-Id": UUID().uuidString] }]
/// )
/// ```
public struct OryHeaderInterceptor: OryRequestInterceptor {

    private let headers: @Sendable (URL) async -> [String: String]

    /// - Parameter headers: Returns the headers to add for a request's URL.
    public init(_ headers: @escaping @Sendable (URL) async -> [String: String]) {
        self.headers = headers
    }

    public func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest {
        var request = request
        for (name, value) in await headers(request.url) {
            request.headers[name] = value
        }
        return request
    }
}
