import Foundation

/// Reads the current session (the `/sessions/whoami` endpoint) and revokes it (native logout).
protocol SessionRepository: Sendable {
    func currentSession(sessionToken: String) async throws -> OrySession

    /// Revokes `sessionToken` on the server (native logout). A `401`/`403` — the token is
    /// already invalid — surfaces as ``OryClientError/sessionExpired``, which the caller can
    /// treat as an already-completed logout.
    func revokeSession(sessionToken: String) async throws
}
