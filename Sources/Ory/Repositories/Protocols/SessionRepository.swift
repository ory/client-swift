import Foundation

/// Reads the current session (the `/sessions/whoami` endpoint) and revokes it (native logout).
protocol SessionRepository: Sendable {
    func currentSession(sessionToken: String) async throws -> OrySession

    /// Revokes `sessionToken` on the server (native logout). A dead session (401) or a
    /// token the server does not know (403 without an error id) surfaces as
    /// ``OryClientError/sessionExpired``, which the caller can treat as an already-completed
    /// logout.
    func revokeSession(sessionToken: String) async throws
}
