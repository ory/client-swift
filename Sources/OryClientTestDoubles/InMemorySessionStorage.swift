import Foundation
import OryClient

/// A non-persistent ``OrySessionStorage`` for tests.
///
/// Keeps the token in memory only, so tests stay isolated and never touch the
/// Keychain. Implemented as an `actor`, so it is thread-safe at compile time with no
/// locks.
///
/// ```swift
/// let storage = InMemorySessionStorage(initialToken: "ory_st_test")
/// let client = OryClient(
///     configuration: .init(projectURL: url, sessionStorage: storage)
/// )
/// ```
public actor InMemorySessionStorage: OrySessionStorage {

    private var token: String?

    /// Creates an in-memory storage.
    ///
    /// - Parameter initialToken: The token to start with, or `nil` for an empty store.
    public init(initialToken: String? = nil) {
        self.token = initialToken
    }

    public func sessionToken() async throws -> String? {
        token
    }

    public func store(sessionToken: String) async throws {
        token = sessionToken
    }

    public func clear() async throws {
        token = nil
    }
}
