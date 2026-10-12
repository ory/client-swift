import Foundation

/// A response the client has received, exposed to a ``OryResponseInterceptor`` for
/// inspection or adaptation. The status, headers, and body the client goes on to decode
/// are whatever the last interceptor returns.
public struct OryReceivedResponse: Sendable {

    /// The request this response is for, as it was sent (with the session token applied).
    public let request: OryOutgoingRequest

    /// The HTTP status code.
    public var statusCode: Int

    /// The response headers.
    public var headers: [String: String]

    /// The response body.
    public var body: Data

    public init(request: OryOutgoingRequest, statusCode: Int, headers: [String: String], body: Data) {
        self.request = request
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Inspects or adapts the client's responses before they are decoded.
///
/// Conform a type and pass it in ``OryClientConfiguration/responseInterceptors``.
/// Interceptors run in array order, each receiving the previous one's output. Use them to
/// observe responses (for logging or breadcrumbs) or, rarely, to rewrite a body before it
/// is decoded.
///
/// - Note: A response interceptor never sees a transport failure — a request that fails
///   before a response arrives throws instead. Use an ``OryNetworkObserver`` to observe
///   those.
public protocol OryResponseInterceptor: Sendable {
    func intercept(_ response: OryReceivedResponse) async throws -> OryReceivedResponse
}
