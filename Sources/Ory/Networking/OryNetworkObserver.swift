import Foundation

/// A network request the client is about to send.
///
/// Sensitive header values (such as the session token) are redacted, and request
/// bodies are never included, so events are safe to log.
public struct OryNetworkRequest: Sendable, Hashable {

    /// The HTTP method, e.g. `GET` or `POST`.
    public let method: String

    /// The request URL.
    public let url: URL

    /// The request headers, with sensitive values redacted.
    public let headers: [String: String]
}

/// A network response the client received.
public struct OryNetworkResponse: Sendable, Hashable {

    /// The request this response is for.
    public let request: OryNetworkRequest

    /// The HTTP status code.
    public let statusCode: Int

    /// How long the request took.
    public let duration: TimeInterval
}

/// Observe the client's network activity for logging, metrics, or breadcrumbs.
///
/// Conform a type and pass it as ``OryClientConfiguration/networkObserver`` to receive
/// callbacks for every request — for example to forward to Sentry or print in debug
/// builds. All methods have default no-op implementations, so override only what you
/// need.
///
/// ```swift
/// struct SentryObserver: OryNetworkObserver {
///     func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable) {
///         SentrySDK.capture(error: error)
///     }
/// }
/// ```
///
/// - Important: Callbacks may arrive on a background thread.
public protocol OryNetworkObserver: Sendable {

    /// Called just before a request is sent.
    func clientWillSend(_ request: OryNetworkRequest)

    /// Called when a response is received, regardless of status code.
    func clientDidReceive(_ response: OryNetworkResponse)

    /// Called when a request fails at the transport level (no response).
    func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable)
}

public extension OryNetworkObserver {
    func clientWillSend(_ request: OryNetworkRequest) {}
    func clientDidReceive(_ response: OryNetworkResponse) {}
    func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable) {}
}

/// A ready-made ``OryNetworkObserver`` that prints requests and responses.
///
/// Handy in debug builds:
///
/// ```swift
/// let config = OryClientConfiguration(
///     projectURL: projectURL,
///     networkObserver: OryConsoleNetworkObserver()
/// )
/// ```
public struct OryConsoleNetworkObserver: OryNetworkObserver {

    public init() {}

    public func clientWillSend(_ request: OryNetworkRequest) {
        // nosemgrep: oryclient-no-url-or-request-logging -- Opt-in debug observer (config default is nil). Sensitive headers are redacted and bodies excluded in OryNetworkRequest, so only method + URL is printed.
        print("[OryClient] → \(request.method) \(request.url.absoluteString)")
    }

    public func clientDidReceive(_ response: OryNetworkResponse) {
        let milliseconds = Int(response.duration * 1000)
        // nosemgrep: oryclient-no-url-or-request-logging -- Opt-in debug observer (config default is nil). Sensitive headers are redacted and bodies excluded in OryNetworkRequest, so only method + URL is printed.
        print("[OryClient] ← \(response.statusCode) \(response.request.url.absoluteString) (\(milliseconds)ms)")
    }

    public func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable) {
        // nosemgrep: oryclient-no-url-or-request-logging -- Opt-in debug observer (config default is nil). Sensitive headers are redacted and bodies excluded in OryNetworkRequest, so only method + URL is printed.
        print("[OryClient] ✗ \(request.method) \(request.url.absoluteString): \(error)")
    }
}
