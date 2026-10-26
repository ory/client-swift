import Foundation
import OryClientTestDoubles
import Testing
@testable import OryClient

@Suite("Device operation concurrency")
struct DeviceOperationConcurrencyTests {
    private let sealingKeys = InsecureEphemeralPINSealingKeyProvider()

    enum Operation: CaseIterable, Sendable {
        case enroll, enrollPIN, enrollBiometric, reset, remove, removeListed, forget
        case loginPIN, loginBiometric, stepUp, stepUpPIN, stepUpBiometric

        func run(_ client: OryClient) async throws {
            switch self {
            case .enroll: try await client.enrollDevice(name: "iPhone")
            case .enrollPIN: try await client.enrollDevice(name: "iPhone", protection: .pin("1234"))
            case .enrollBiometric: try await client.enrollDevice(name: "iPhone", protection: .biometrics)
            case .reset: try await client.resetDevicePIN(newPin: "1234")
            case .remove: try await client.removeDevice()
            case .removeListed:
                try await client.removeDevice(OryEnrolledDevice(
                    clientKeyID: "key", name: "iPhone", enrolledAt: .distantPast, platform: .iOS,
                    userVerification: .pin, isLocked: false, isCurrentDevice: true
                ))
            case .forget: try await client.forgetDevice()
            case .loginPIN: _ = try await client.loginWithDevice(pin: "1234")
            case .loginBiometric: _ = try await client.loginWithDevice()
            case .stepUp: _ = try await client.authenticateWithDevice()
            case .stepUpPIN: _ = try await client.authenticateWithDevice(pin: "1234")
            case .stepUpBiometric: _ = try await client.authenticateWithDevice()
            }
        }
    }

    private func makeClient(store: any OryDeviceKeyStore, repository: FakeFrontendRepository) -> OryClient {
        OryClient(
            storage: InMemorySessionStorage(initialToken: "session"),
            frontend: repository,
            deviceAuthn: repository,
            deviceKeyStore: store,
            deviceAuthenticator: FakeDeviceKeyAuthenticator(),
            biometricAuthenticator: FakeBiometricAuthenticator(),
            pinSealingKeyProvider: sealingKeys
        )
    }

    private func pinKey() throws -> OryStoredDeviceKey {
        let vault = DevicePINVault(sealingKeyProvider: sealingKeys)
        let secret = try vault.protect(pinSecret: Data(repeating: 1, count: 32), pinString: "1234")
        return OryStoredDeviceKey(clientKeyID: "key", localKeyID: "local", pinSecret: secret, userVerification: .pin, identityID: "identity-1")
    }

    @Test("A second client cannot rotate while the first rotation is awaiting its response")
    func concurrentRotation() async throws {
        // Given two clients sharing one local key and a committed rotation whose response is held.
        let gate = DeviceTestGate()
        let repository = FakeFrontendRepository(afterDeviceMutation: { await gate.holdFirst() })
        let store = InMemoryDeviceKeyStore(initial: try pinKey())
        let first = makeClient(store: store, repository: repository)
        let second = makeClient(store: store, repository: repository)
        let pending = Task { try await first.resetDevicePIN(newPin: "1111") }
        await gate.waitUntilHeld()

        // When a second rotation would otherwise overtake the first response.
        do {
            try await second.resetDevicePIN(newPin: "2222")
            Issue.record("An overlapping device operation must be rejected")
        } catch {
            expectInProgress(error)
        }
        #expect(await repository.submitCallCount == 1)

        await gate.release()
        try await pending.value

        // Then the first operation remains usable, and a later rotation can proceed.
        try await second.resetDevicePIN(newPin: "3333")
        #expect(await repository.submitCallCount == 2)
        let stored = try #require(await store.stored?.pinSecret)
        let vault = DevicePINVault(sealingKeyProvider: sealingKeys)
        #expect(try vault.unlock(stored, pinString: "3333") == Data(repeating: 7, count: 32))
    }

    @Test("An old device removal preserves a replacement local key", arguments: [false, true])
    func removalPreservesReplacement(sameID: Bool) async throws {
        // Given a removal response arriving after storage has a replacement record.
        let store = InMemoryDeviceKeyStore(initial: try pinKey())
        let replacement = OryStoredDeviceKey(clientKeyID: sameID ? "key" : "replacement", localKeyID: "new-local", userVerification: .none, identityID: "identity-1")
        let repository = FakeFrontendRepository(afterDeviceMutation: { try await store.store(replacement) })
        let client = makeClient(store: store, repository: repository)

        // When the old key is revoked.
        try await client.removeDevice()

        // Then cleanup applies only to the record that was removed.
        #expect(await store.stored == replacement)
        #expect(await store.clearCallCount == 0)
    }

    @Test("Every device operation rejects overlap before using shared key material", arguments: Operation.allCases)
    func sharedKeyOperations(operation: Operation) async throws {
        // Given one client's rotation is active, and another client uses the same slot.
        let gate = DeviceTestGate()
        let repository = FakeFrontendRepository(afterDeviceMutation: { await gate.holdFirst() })
        let key = try pinKey()
        let store = InMemoryDeviceKeyStore(initial: key)
        let first = makeClient(store: store, repository: repository)
        let second = makeClient(store: store, repository: repository)
        let pending = Task { try await first.resetDevicePIN(newPin: "1111") }
        await gate.waitUntilHeld()

        // When another operation tries to use or replace that key.
        do {
            try await operation.run(second)
            Issue.record("Expected the active operation to exclude overlap")
        } catch {
            expectInProgress(error)
        }

        // Then the second operation neither submits a request nor changes local state.
        #expect(await repository.submitCallCount == 1)
        #expect(await store.stored == key)
        await gate.release()
        try await pending.value
    }

    @Test("A failed removal cleanup read reports storage failure and releases the scope")
    func removalReadFailure() async throws {
        let key = try pinKey()
        let base = InMemoryDeviceKeyStore(initial: key)
        let store = RemovalReadFailureStore(base: base)
        let repository = FakeFrontendRepository(afterDeviceMutation: { await store.failNextRead() })
        let client = makeClient(store: store, repository: repository)

        do {
            try await client.removeDevice()
            Issue.record("Removal must report an unreadable local record after server revocation")
        } catch OryClientError.storage {
        } catch { Issue.record(error) }
        #expect(await base.stored == key)
        #expect(await base.clearCallCount == 0)
        #expect(await repository.submitCallCount == 1)

        let second = makeClient(store: store, repository: repository)
        try await second.forgetDevice()
        #expect(await base.stored == nil)
        #expect(await base.clearCallCount == 1)
    }

    @Test("Independent device stores can operate while another store is busy")
    func independentStores() async throws {
        let gate = DeviceTestGate()
        let repository = FakeFrontendRepository(afterDeviceMutation: { await gate.holdFirst() })
        let first = makeClient(store: InMemoryDeviceKeyStore(initial: try pinKey()), repository: repository)
        let otherStore = InMemoryDeviceKeyStore(initial: try pinKey())
        let second = makeClient(store: otherStore, repository: FakeFrontendRepository())
        let pending = Task { try await first.resetDevicePIN(newPin: "1111") }
        await gate.waitUntilHeld()

        do {
            try await second.forgetDevice()
            #expect(await otherStore.stored == nil)
        } catch { Issue.record(error) }
        await gate.release()
        try await pending.value
    }

    @Test("Server failure or cancellation releases the device operation scope", arguments: [false, true])
    func failureReleasesScope(cancelled: Bool) async throws {
        let gate = DeviceTestGate()
        let repository = FakeFrontendRepository(afterDeviceMutation: {
            await gate.holdFirst()
            if cancelled { throw CancellationError() }
            throw OryClientError.reauthenticationRequired
        })
        let store = InMemoryDeviceKeyStore(initial: try pinKey())
        let first = makeClient(store: store, repository: repository)
        let second = makeClient(store: store, repository: repository)
        let pending = Task { try await first.resetDevicePIN(newPin: "1111") }
        await gate.waitUntilHeld()
        if cancelled { pending.cancel() }
        await gate.release()
        do {
            try await pending.value
            Issue.record("Expected the pending operation to fail")
        } catch is CancellationError {
            #expect(cancelled)
        } catch OryClientError.reauthenticationRequired {
            #expect(!cancelled)
        }

        try await second.forgetDevice()
        #expect(await store.stored == nil)
    }

    @Test("An already-cancelled device operation leaves storage untouched")
    func cancelledBeforeEntry() async throws {
        let gate = DeviceTestGate()
        let key = try pinKey()
        let store = InMemoryDeviceKeyStore(initial: key)
        let client = makeClient(store: store, repository: FakeFrontendRepository())
        let task = Task {
            await gate.holdFirst()
            try await client.forgetDevice()
        }
        await gate.waitUntilHeld()
        task.cancel()
        await gate.release()
        do {
            try await task.value
            Issue.record("Expected cancellation before storage access")
        } catch is CancellationError {}
        #expect(await store.stored == key)
        try await client.forgetDevice()
        #expect(await store.stored == nil)
    }

    @Test("Custom stores without a scope override coordinate across wrapper instances")
    func defaultCustomStoreScope() async throws {
        let gate = DeviceTestGate()
        let repository = FakeFrontendRepository(afterDeviceMutation: { await gate.holdFirst() })
        let store = InMemoryDeviceKeyStore(initial: try pinKey())
        let first = makeClient(store: DefaultScopeStore(base: store), repository: repository)
        let second = makeClient(store: DefaultScopeStore(base: store), repository: repository)
        let pending = Task { try await first.resetDevicePIN(newPin: "1111") }
        await gate.waitUntilHeld()

        do {
            try await second.forgetDevice()
            Issue.record("Stores sharing the default scope must exclude overlap")
        } catch { expectInProgress(error) }
        #expect(await store.clearCallCount == 0)
        await gate.release()
        try await pending.value
        try await second.forgetDevice()
    }

    @Test("Keychain aliases for one service share a scope while other services remain independent")
    func keychainScopes() async throws {
        // Non-nil access groups avoid install-marker cleanup; this test performs no Keychain I/O.
        let service = UUID().uuidString
        let original = OryKeychainDeviceKeyStore(service: service, accessGroup: "group-one")
        let alias = OryKeychainDeviceKeyStore(service: service, accessGroup: "group-two")
        let independent = OryKeychainDeviceKeyStore(service: service + ":other", accessGroup: "group-one")
        let coordinator = DeviceOperationCoordinator()
        let gate = DeviceTestGate()
        let pending = Task {
            try await coordinator.perform(scope: original.deviceOperationScope) { await gate.holdFirst() }
        }
        await gate.waitUntilHeld()

        do {
            _ = try await coordinator.perform(scope: alias.deviceOperationScope) {
                Issue.record("A Keychain alias must not enter an active service scope")
            }
        } catch { expectInProgress(error) }
        do {
            let result = try await coordinator.perform(scope: independent.deviceOperationScope) { 42 }
            #expect(result == 42)
        } catch { Issue.record(error) }
        await gate.release()
        try await pending.value
    }

    private func expectInProgress(_ error: any Error, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case OryClientError.deviceAuthenticationOperationInProgress = error else {
            Issue.record("Expected deviceAuthenticationOperationInProgress, got \(error)", sourceLocation: sourceLocation)
            return
        }
    }
}

private struct DefaultScopeStore: OryDeviceKeyStore {
    let base: InMemoryDeviceKeyStore
    func enrolledKey() async throws -> OryStoredDeviceKey? { try await base.enrolledKey() }
    func store(_ key: OryStoredDeviceKey) async throws { try await base.store(key) }
    func clear() async throws { try await base.clear() }
}

private actor RemovalReadFailureStore: OryDeviceKeyStore {
    nonisolated let deviceOperationScope: String
    private let base: InMemoryDeviceKeyStore
    private var shouldFailRead = false

    init(base: InMemoryDeviceKeyStore) {
        self.base = base
        deviceOperationScope = base.deviceOperationScope
    }

    func failNextRead() { shouldFailRead = true }

    func enrolledKey() async throws -> OryStoredDeviceKey? {
        if shouldFailRead {
            shouldFailRead = false
            throw CocoaError(.fileReadNoPermission)
        }
        return try await base.enrolledKey()
    }

    func store(_ key: OryStoredDeviceKey) async throws { try await base.store(key) }
    func clear() async throws { try await base.clear() }
}

private actor DeviceTestGate {
    private var held = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<Void, Never>?

    func holdFirst() async {
        guard !held else { return }
        held = true
        arrival?.resume()
        arrival = nil
        guard !released else { return }
        await withCheckedContinuation { response = $0 }
    }

    func waitUntilHeld() async {
        guard !held else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        released = true
        response?.resume()
        response = nil
    }
}
