import Foundation
import OryClient

/// A non-persistent ``OryDeviceKeyStore`` for tests.
///
/// Keeps the enrolled device key in memory only, so tests stay isolated and never
/// touch the Keychain, and records what was stored and cleared so tests can assert
/// on it. Implemented as an `actor`, so it is thread-safe at compile time.
///
/// ```swift
/// let store = InMemoryDeviceKeyStore()
/// let client = OryClient(
///     configuration: .init(projectURL: url, deviceKeyStore: store)
/// )
/// try await client.enrollDevice(name: "Test device")
/// #expect(await store.stored != nil)
/// ```
public actor InMemoryDeviceKeyStore: OryDeviceKeyStore {

    /// Identifies this store instance so clients sharing it coordinate device operations,
    /// while separate in-memory stores remain independent.
    public nonisolated let deviceOperationScope = UUID().uuidString

    /// The currently stored key, if any.
    public private(set) var stored: OryStoredDeviceKey?

    /// How many times ``clear()`` was called.
    public private(set) var clearCallCount = 0

    /// Creates an in-memory store.
    ///
    /// - Parameter initial: The key to start with, or `nil` for an empty store.
    public init(initial: OryStoredDeviceKey? = nil) {
        self.stored = initial
    }

    public func enrolledKey() async throws -> OryStoredDeviceKey? { stored }

    public func store(_ key: OryStoredDeviceKey) async throws { stored = key }

    public func clear() async throws {
        clearCallCount += 1
        stored = nil
    }
}
