import Foundation
import OryClient
import OryClientTestDoubles
import Testing
@testable import OryClientExample

@MainActor
struct DeviceAuthnOperationTests {

    @Test("An overlapping device action preserves the active action's busy state")
    func overlappingActionPreservesBusyState() async {
        let store = SuspendedClearDeviceKeyStore()
        let client = OryClient(configuration: OryClientConfiguration(
            projectURL: URL(string: "https://example.invalid")!,
            sessionStorage: InMemorySessionStorage(),
            deviceKeyStore: store,
            pinSealingKeyProvider: InsecureEphemeralPINSealingKeyProvider()
        ))
        let viewModel = DeviceAuthnViewModel(client: client, session: Self.session, onSessionChanged: { _ in })
        await viewModel.load()
        #expect(viewModel.isEnrolled)
        let forgetting = Task { await viewModel.forget() }
        await store.waitUntilClearStarts()

        await viewModel.resetPIN("1357")

        #expect(viewModel.isBusy)
        #expect(viewModel.status == .idle)
        #expect(viewModel.isEnrolled)
        await store.releaseClear()
        await forgetting.value
        #expect(!viewModel.isBusy)
        #expect(!viewModel.isEnrolled)
        guard case .success = viewModel.status else {
            Issue.record("The original device action should complete successfully")
            return
        }
    }

    @Test("A device operation conflict displays an error without changing enrollment")
    func operationConflictPreservesEnrollment() async {
        var changedSession: OrySession?
        let client = OryClientStub(
            deviceEnrollmentResult: .success(.enrolled(.pin)),
            resetDevicePINResult: .failure(.deviceAuthenticationOperationInProgress)
        )
        let viewModel = DeviceAuthnViewModel(
            client: client, session: Self.session, onSessionChanged: { changedSession = $0 }
        )
        await viewModel.load()

        await viewModel.resetPIN("1357")

        #expect(viewModel.status == .failure(OryClientError.deviceAuthenticationOperationInProgress.localizedDescription))
        #expect(viewModel.isEnrolled)
        #expect(viewModel.isPINEnrolled)
        #expect(viewModel.assuranceLevel == .aal1)
        #expect(changedSession == nil)
        #expect(!viewModel.isBusy)
    }

    @Test("Device operation conflicts leave PIN attempts available and allow a later sign-in")
    func operationConflictDoesNotConsumePINAttempts() async {
        var signedIn: OrySession?
        let client = OryClientStub(loginWithDeviceResult: .failure(.deviceAuthenticationOperationInProgress))
        let viewModel = PINLoginViewModel(client: client, onSignedIn: { signedIn = $0 })

        for _ in 0..<3 {
            await viewModel.login(pin: "1357")
        }

        #expect(viewModel.errorMessage == OryClientError.deviceAuthenticationOperationInProgress.localizedDescription)
        #expect(!viewModel.isLikelyLocked)
        #expect(!viewModel.isBusy)
        #expect(signedIn == nil)

        await client.setLoginWithDeviceResult(.failure(.deviceAuthenticationInvalidPIN))
        await viewModel.login(pin: "2468")
        await viewModel.login(pin: "2468")
        #expect(!viewModel.isLikelyLocked)

        await client.setLoginWithDeviceResult(.success(OryAuthenticatedSession(session: Self.session)))
        await viewModel.login(pin: "1357")
        #expect(signedIn?.id == "device-session")
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isBusy)
    }

    private static let session = OrySession(
        id: "device-session",
        isActive: true,
        expiresAt: nil,
        authenticatedAt: nil,
        authenticatorAssuranceLevel: .aal1,
        identity: OryIdentity(id: "device-identity", schemaID: "default")
    )
}

private actor SuspendedClearDeviceKeyStore: OryDeviceKeyStore {
    nonisolated let deviceOperationScope = UUID().uuidString
    private var key: OryStoredDeviceKey? = OryStoredDeviceKey(
        clientKeyID: "device-key", localKeyID: "local-key", userVerification: .none
    )
    private var clearStarted = false
    private var clearContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func enrolledKey() async throws -> OryStoredDeviceKey? { key }

    func store(_ key: OryStoredDeviceKey) async throws { self.key = key }

    func clear() async throws {
        await withCheckedContinuation { continuation in
            clearContinuation = continuation
            clearStarted = true
            startContinuation?.resume()
            startContinuation = nil
        }
        key = nil
    }

    func waitUntilClearStarts() async {
        guard !clearStarted else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func releaseClear() {
        clearContinuation?.resume()
        clearContinuation = nil
    }
}
