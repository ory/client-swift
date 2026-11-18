import Foundation

/// Runs one client's reads and writes of the stored session token one at a time, so a decision
/// based on the token a request was sent with cannot clear or overwrite a token that another
/// call stored while the request was in flight.
///
/// The storage methods are `async`, so actor isolation alone would let another call run between
/// a read and the write that depends on it. Each operation waits for the previous one instead.
actor SessionTokenStore {

    private let storage: OrySessionStorage
    private var tail: Task<Void, Never>?

    init(storage: OrySessionStorage) {
        self.storage = storage
    }

    func token() async throws -> String? {
        try await serialized { try await $0.sessionToken() }
    }

    func store(_ token: String) async throws {
        try await serialized { try await $0.store(sessionToken: token) }
    }

    func clear() async throws {
        try await serialized { try await $0.clear() }
    }

    /// Clears the stored token only while it is still `token`.
    func clear(ifStillStoring token: String) async throws {
        try await serialized { storage in
            if try await storage.sessionToken() == token {
                try await storage.clear()
            }
        }
    }

    /// Stores `replacement` only while `current` is still the stored token.
    ///
    /// - Returns: Whether `current` was still stored. A `nil` or unchanged `replacement` writes
    ///   nothing.
    func replace(_ current: String, with replacement: String?) async throws -> Bool {
        try await serialized { storage in
            guard try await storage.sessionToken() == current else {
                return false
            }
            if let replacement, replacement != current {
                try await storage.store(sessionToken: replacement)
            }
            return true
        }
    }

    private func serialized<T: Sendable>(
        _ operation: @escaping @Sendable (OrySessionStorage) async throws -> T
    ) async throws -> T {
        let previous = tail
        let storage = storage
        let task = Task {
            await previous?.value
            return try await operation(storage)
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
