import Foundation

/// The transport seam.
///
/// Repositories depend on this protocol, not the concrete ``URLSessionHTTPClient``, so
/// tests can inject a client that returns canned responses and exercise status handling,
/// decoding, and mapping without the network.
protocol HTTPClient: Sendable {
    func send<R: FrontendRequest>(_ request: R) async throws -> HTTPResponse<R.Response>
}
