import Foundation

extension OryClient: OrySessionManagement {

    public func currentSession() async throws -> OrySession {
        let token = try await requireSessionToken()
        do {
            return try await session.currentSession(sessionToken: token)
        } catch OryClientError.sessionExpired {
            // The server rejected the token outright, so keeping it would leave a dead
            // credential at rest and make every later call report an expired session where
            // "not signed in" is the truth. A second-factor demand is not a rejection —
            // that token is valid and must survive the step-up.
            try? await storage.clear()
            throw OryClientError.sessionExpired
        }
    }

    public func logout() async throws {
        let token: String?
        do {
            token = try await storage.sessionToken()
        } catch {
            throw Self.storageError(error)
        }
        guard let token, !token.isEmpty else {
            // Not signed in — nothing to revoke or clear.
            return
        }

        // Revoke on the server so a leaked token cannot outlive sign-out. A token already
        // invalid server-side (401/403 → sessionExpired) is treated as an already-completed
        // logout, not a failure. Any other failure is surfaced *after* the local token is
        // cleared, so the user is always signed out on this device.
        var revokeError: OryClientError?
        do {
            try await session.revokeSession(sessionToken: token)
        } catch OryClientError.sessionExpired {
        } catch let error as OryClientError {
            revokeError = error
        }

        do {
            try await storage.clear()
        } catch {
            throw Self.storageError(error)
        }

        if let revokeError {
            throw revokeError
        }
    }
}
