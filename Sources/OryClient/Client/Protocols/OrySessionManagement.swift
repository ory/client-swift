import Foundation

/// Reading and ending the current session.
public protocol OrySessionManagement: Sendable {

    /// Returns the current session for the stored session token.
    ///
    /// Use this on launch to decide whether the user is signed in.
    ///
    /// ```swift
    /// do {
    ///     let session = try await client.currentSession()
    ///     // Signed in — show the app.
    /// } catch OryClientError.notAuthenticated, OryClientError.sessionExpired {
    ///     // Show sign-in.
    /// }
    /// ```
    ///
    /// - Returns: The active ``OrySession``.
    /// - Throws: ``OryClientError/notAuthenticated`` if no token is stored,
    ///   ``OryClientError/sessionExpired`` if the server rejected the token, or
    ///   another ``OryClientError`` on network, storage, or decoding failure.
    func currentSession() async throws -> OrySession

    /// Signs the user out: revokes the session on the server, then clears the stored token.
    ///
    /// Revoking server-side means a token that leaked earlier cannot outlive sign-out — it is
    /// invalidated immediately rather than remaining valid until it expires. The local token is
    /// **always** cleared, so the user is signed out on this device even if the server cannot be
    /// reached; in that case the call still throws so you can surface the failure. A token the
    /// server already considers invalid is treated as an already-completed logout, not an error.
    /// If no token is stored, this does nothing.
    ///
    /// The enrolled device credential (PIN or biometric) is left intact, so the user can sign
    /// back in with it. Use ``OryDeviceManagement/removeDevice()`` or
    /// ``OryDeviceManagement/forgetDevice()`` to remove that separately.
    ///
    /// ```swift
    /// do {
    ///     try await client.logout()
    /// } catch {
    ///     // Already signed out locally; tell the user the server could not be reached.
    /// }
    /// ```
    ///
    /// - Throws: ``OryClientError/network(underlying:)`` or ``OryClientError/server(status:messages:)``
    ///   if the server revoke failed (the local token is cleared regardless), or
    ///   ``OryClientError/storage(underlying:)`` if the token could not be cleared.
    func logout() async throws
}
