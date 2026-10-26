import Foundation

/// A response the client has received, exposed to a ``OryResponseInterceptor`` for
/// inspection. Every property is read-only: the client decodes the response as it arrived.
public struct OryReceivedResponse: Sendable {

    /// The request this response is for, as interceptors saw it: without the session token,
    /// and with credential values in its body redacted.
    public let request: OryOutgoingRequest

    /// The HTTP status code.
    public let statusCode: Int

    /// The response headers.
    public let headers: [String: String]

    /// A copy of the JSON response body with credential values — such as `session_token` —
    /// replaced by `"[REDACTED]"`, so it is safe to log.
    public let body: Data

    /// Creates a response, for example to unit-test your own interceptor.
    public init(request: OryOutgoingRequest, statusCode: Int, headers: [String: String], body: Data) {
        self.request = request
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Inspects the client's responses before they are decoded.
///
/// Conform a type and pass it in ``OryClientConfiguration/responseInterceptors``, for example
/// to log responses or record breadcrumbs. Interceptors run in array order. Throwing fails the
/// call: an ``OryClientError`` is rethrown as is, and any other error is wrapped in
/// ``OryClientError/unexpectedResponse(underlying:)``.
///
/// ```swift
/// struct BreadcrumbInterceptor: OryResponseInterceptor {
///     func intercept(_ response: OryReceivedResponse) async throws {
///         Breadcrumbs.add("\(response.statusCode) \(response.request.url.path)")
///     }
/// }
/// ```
///
/// - Note: A response interceptor never sees a transport failure — a request that fails
///   before a response arrives throws instead. Use an ``OryNetworkObserver`` to observe
///   those.
public protocol OryResponseInterceptor: Sendable {
    func intercept(_ response: OryReceivedResponse) async throws
}
