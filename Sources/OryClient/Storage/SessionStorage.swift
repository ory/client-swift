import Foundation

/// Persists the credentials ``OryClient`` needs between launches.
///
/// The session token returned by a successful authentication is sent as the
/// `X-Session-Token` header on every authenticated request, so it must outlive a
/// single app session. ``OryClient`` reads and writes it exclusively through this
/// protocol, which lets you swap the backing store — for example to share a token
/// across app extensions via a Keychain access group, or to inject an in-memory
/// store in tests.
///
/// The default implementation is ``OryKeychainSessionStorage``. Conform your own type
/// when you need different behavior — but keep the token out of `UserDefaults` and any
/// other unencrypted, backed-up store: it authenticates every request the user makes.
///
/// ```swift
/// actor SharedGroupSessionStorage: OrySessionStorage {
///     func sessionToken() async throws -> String? { /* ... */ }
///     func store(sessionToken: String) async throws { /* ... */ }
///     func clear() async throws { /* ... */ }
/// }
/// ```
///
/// The methods are `async` so implementations can be backed by an `actor` or any
/// async store and stay thread-safe at compile time, without locks.
public protocol OrySessionStorage: Sendable {

    /// Returns the stored session token, or `nil` when no session is stored.
    ///
    /// - Returns: The session token, or `nil` if the user is not authenticated.
    /// - Throws: An error if the underlying store cannot be read.
    func sessionToken() async throws -> String?

    /// Stores the session token, replacing any previously stored value.
    ///
    /// - Parameter sessionToken: The token returned by a successful authentication.
    /// - Throws: An error if the underlying store cannot be written.
    func store(sessionToken: String) async throws

    /// Removes the stored session token, for example on sign-out.
    ///
    /// Clearing an empty store is not an error.
    ///
    /// - Throws: An error if the underlying store cannot be cleared.
    func clear() async throws
}
