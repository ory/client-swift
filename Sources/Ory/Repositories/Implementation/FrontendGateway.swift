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
            case .some(.sessionInactive):
                return .sessionExpired
            case .some(.sessionVerifiedAddressRequired):
                if let verification = envelope.continuation.verification {
                    return .addressVerificationRequired(verification)
                }
                return .server(status: response.status, id: envelope.id, messages: envelope.messages)
            case .none where response.status == 401:
                // Whoami reports a missing, invalid, expired, or revoked token as a 401 without an id.
                return .sessionExpired
            default:
                // Callers clear the stored token on sessionExpired, so an unrecognized 403, which
                // may come from a proxy in front of Ory, must not sign the user out.
                return .server(status: response.status, id: envelope.id, messages: envelope.messages)
            }
        case 410:
            return .flowExpired(replacementFlowID: envelope.useFlowID)
        case 429:
            return .rateLimited(retryAfter: Self.retryAfter(from: response.headers))
        default:
            if response.status == 422, let redirectURL = envelope.redirectBrowserTo {
                return .browserLocationChangeRequired(redirectURL: redirectURL)
            }
            return .server(status: response.status, id: envelope.id, messages: envelope.messages)
        }
    }

    /// Reads `Retry-After`, which Ory sends as a whole number of seconds. The HTTP-date form
    /// the RFC also allows is not produced by Ory's rate limiter, so it is not parsed.
    private static func retryAfter(from headers: [String: String]) -> TimeInterval? {
        headers["retry-after"].flatMap(TimeInterval.init)
    }
}
