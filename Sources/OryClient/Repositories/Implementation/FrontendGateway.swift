import Foundation

/// Shared context for the Frontend API repositories: the transport plus the status-to-error
/// mapping every repository uses. Both ``LiveFrontendRepository`` and
/// ``LiveDeviceAuthnRepository`` hold one, built over the same ``HTTPClient``.
struct FrontendGateway: Sendable {

    let client: any HTTPClient

    func send<R: FrontendRequest>(_ request: R) async throws -> HTTPResponse<R.Response> {
        try await client.send(request)
    }

    /// Returns a 2xx body, or maps the response to an error. For endpoints whose only success
    /// shape is the request's declared ``FrontendRequest/Response``.
    func decoded<T: Decodable & Sendable>(_ response: HTTPResponse<T>) throws -> T {
        guard (200..<300).contains(response.status) else {
            throw error(from: response)
        }
        return try response.success()
    }

    /// Maps a non-2xx response to the ``OryClientError`` describing what the app should do.
    ///
    /// The classification is driven by Ory's machine-readable `error.id` rather than the status
    /// alone, because one status covers several conditions that call for different reactions —
    /// a 403 is "prove a second factor", "enroll one first", or "re-authenticate" depending on
    /// the id. Conditions with no dedicated case keep their id in
    /// ``OryClientError/server(status:id:messages:)``, so an id this build predates stays
    /// visible to the app instead of being flattened away.
    func error<T>(from response: HTTPResponse<T>) -> OryClientError {
        let envelope = ErrorMapper.envelope(from: response.data)

        switch response.status {
        case 401, 403:
            switch envelope.id {
            case .some(.sessionAAL2Required):
                return .secondFactorRequired
            case .some(.sessionAAL2EnrollmentRequired):
                return .secondFactorEnrollmentRequired
            case .some(.sessionRefreshRequired):
                return .reauthenticationRequired
            default:
                // Conservative: an authentication failure this build does not recognize is
                // treated as a dead session rather than passed off as a generic server error.
                return .sessionExpired
            }
        case 410:
            return .flowExpired(replacementFlowID: envelope.useFlowID)
        case 429:
            return .rateLimited(retryAfter: Self.retryAfter(from: response.headers))
        default:
            return .server(status: response.status, id: envelope.id, messages: envelope.messages)
        }
    }

    /// Reads `Retry-After`, which Ory sends as a whole number of seconds. The HTTP-date form
    /// the RFC also allows is not produced by Ory's rate limiter, so it is not parsed.
    private static func retryAfter(from headers: [String: String]) -> TimeInterval? {
        headers["retry-after"].flatMap(TimeInterval.init)
    }
}
