import Foundation

/// A request the client is about to send, exposed to a ``OryRequestInterceptor`` for
/// mutation. Change the headers, and — rarely — the URL, method, or body.
///
/// ``headers`` already contains `Accept`, `Content-Type` for a request with a body, and
/// `X-Ory-Client`, which tells Ory the client package, its version, and the OS — for example
/// `ory-client-swift/0.1.0 (iOS 18.2.0)`. It carries no user or device identifiers.
///
/// The session-token header is applied by the client *after* every interceptor runs, so
/// an interceptor cannot read or overwrite it here.
public struct OryOutgoingRequest: Sendable {

    /// The HTTP method, e.g. `GET` or `POST`.
    public var method: String

    /// The request URL.
    public var url: URL

    /// The request headers.
    public var headers: [String: String]

    /// The request body, if any.
    public var body: Data?

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
/// headers such as tracing or correlation IDs, or otherwise adjust every request.
/// Interceptors run in array order, each receiving the previous one's output.
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
