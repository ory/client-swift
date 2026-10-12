import Foundation

/// A single call against Ory's Frontend API, described declaratively.
///
/// Each endpoint is one small conforming struct under `Networking/Requests/`: it names
/// its path/method/body and, through ``Response``, the DTO a successful (2xx) response
/// decodes into. An ``HTTPClient`` executes it. The repository layer interprets the
/// status and maps the DTO to a domain model.
///
/// Only the 2xx shape is declared here. Ory's flow endpoints also answer `400` with the
/// flow to re-render — that is a control path, not the endpoint's response type, so the
/// repository decodes it explicitly from ``HTTPResponse`` where it happens.
protocol FrontendRequest: Sendable {

    /// The DTO a successful (2xx) response decodes into.
    associatedtype Response: Decodable & Sendable

    var method: HTTPMethod { get }
    var target: RequestTarget { get }

    /// The request body, or `nil` for a request that sends none.
    var body: (any Encodable & Sendable)? { get }

    /// How the request authenticates.
    var authorization: RequestAuthorization { get }
}

extension FrontendRequest {
    var body: (any Encodable & Sendable)? { nil }
    var authorization: RequestAuthorization { .none }
}

/// Where a request is sent.
enum RequestTarget: Sendable {

    /// A path relative to the project base URL, with optional query items —
    /// for example `.path("/sessions/whoami")`.
    case path(String, query: [URLQueryItem] = [])

    /// An absolute URL, used when the server dictates it — for example a flow's
    /// `ui.action` submit URL.
    case url(URL)
}

/// How a request authenticates.
enum RequestAuthorization: Sendable {
    case none

    /// Sent as the `X-Session-Token` header. Applied by the transport *after* any
    /// interceptor, so it cannot be overwritten.
    case sessionToken(String)
}
