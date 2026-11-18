import Foundation

/// An authenticated session.
///
/// Returned by ``OryClientProtocol/currentSession()``. Unlike the raw API response,
/// every field here that the server always provides is non-optional, so you can use
/// a session without unwrapping noise.
///
/// ```swift
/// let session = try await client.currentSession()
/// guard session.isActive else { /* sign the user back in */ return }
/// print("Signed in as", session.identity?.id ?? "unknown")
/// ```
public struct OrySession: Sendable, Hashable {

    /// The session's unique identifier.
    public let id: String

    /// Whether the session is currently active. An expired or revoked session is
    /// inactive.
    public let isActive: Bool

    /// When the session expires, if the server provided an expiry.
    public let expiresAt: Date?

    /// When the session was last authenticated. For multi-factor sessions this is
    /// when the most recent factor completed.
    public let authenticatedAt: Date?

    /// How strongly the session is authenticated. See ``OryAuthenticatorAssuranceLevel``.
    public let authenticatorAssuranceLevel: OryAuthenticatorAssuranceLevel

    /// The identity the session belongs to, when included in the response.
    public let identity: OryIdentity?

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - id: The session's unique identifier.
    ///   - isActive: Whether the session is currently active.
    ///   - expiresAt: When the session expires, if known.
    ///   - authenticatedAt: When the session was last authenticated, if known.
    ///   - authenticatorAssuranceLevel: The session's assurance level.
    ///   - identity: The identity the session belongs to, if included.
    public init(
        id: String,
        isActive: Bool,
        expiresAt: Date?,
        authenticatedAt: Date?,
        authenticatorAssuranceLevel: OryAuthenticatorAssuranceLevel,
        identity: OryIdentity?
    ) {
        self.id = id
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.authenticatedAt = authenticatedAt
        self.authenticatorAssuranceLevel = authenticatorAssuranceLevel
        self.identity = identity
    }
}
