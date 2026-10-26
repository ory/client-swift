import OryClient
import OryClientTestDoubles
import Testing
@testable import OryClientExample

@MainActor
struct RecoverySettingsTests {

    private static let recoveryAction = OryInputField(name: .method, kind: .submit, value: "code")
    private static let passwordAction = OryInputField(name: .method, kind: .submit, value: "password")
    private static let profileAction = OryInputField(name: .method, kind: .submit, value: "profile")
    private static let settingsFlow = OryFlow(
        id: "recovery-settings-1", kind: .settings, actions: [passwordAction, profileAction]
    )
    private static let saved = OrySettingsResult(identity: OryIdentity(id: "identity-1", schemaID: "default"))

    @Test("Recovery cannot finish before the required password change")
    func recoveryWaitsForPasswordChange() async {
        // Given recovery will return an existing settings flow
        var finished = false
        let client = OryClientStub(
            createRecoveryFlowResult: .success(OryFlow(id: "recovery-1", kind: .recovery)),
            submitRecoveryFlowResult: .success(.success(OryRecoveryResult(
                settings: OrySettingsHandle(flowID: "recovery-settings-1")
            )))
        )
        let viewModel = RecoveryViewModel(client: client, onFinished: { finished = true })

        // When the email challenge succeeds and completion is attempted
        await viewModel.start()
        await viewModel.submit(pressing: OryInputField(name: .method, kind: .submit, value: "code"))
        viewModel.finish()

        // Then recovery still needs the password step
        #expect(!finished)
    }

    @Test("Recovery loads its exact settings flow and finishes after a password save")
    func recoveryCompletesAfterPasswordSave() async throws {
        // Given a recovered account with an existing settings flow
        var finished = false
        let client = makeClient()
        let recovery = RecoveryViewModel(client: client, onFinished: { finished = true })
        await recovery.start()
        await recovery.submit(pressing: Self.recoveryAction)
        guard case let .settings(settings) = recovery.state else {
            Issue.record("Expected the recovery settings screen")
            return
        }

        // When the exact flow is loaded and a password is successfully saved
        await settings.start()
        #expect(await client.requestedSettingsFlowID == "recovery-settings-1")
        #expect(await client.createSettingsFlowCallCount == 0)
        settings.values[.password] = "A-new-password-123!"
        await settings.submit(pressing: Self.passwordAction)

        // Then the success screen waits for Continue before leaving recovery
        guard case .recovered = recovery.state else {
            Issue.record("Expected completed recovery after the password save")
            return
        }
        #expect(!finished)
        recovery.finish()
        #expect(finished)
    }

    @Test("Saving a profile does not finish password recovery", arguments: [false, true])
    func profileSaveDoesNotCompleteRecovery(requiresVerification: Bool) async {
        // Given a profile save, optionally followed by address verification
        var finished = false
        let client = makeClient()
        if requiresVerification {
            await client.setSubmitSettingsFlowResult(.success(.success(OrySettingsResult(
                identity: Self.saved.identity,
                verification: OryVerificationHandle(flowID: "verification-1", address: "new@example.com")
            ))))
            await client.setGetVerificationFlowResult(.success(OryFlow(id: "verification-1", kind: .verification)))
            await client.setSubmitVerificationFlowResult(.success(.success(OryVerificationResult())))
        }
        let recovery = RecoveryViewModel(client: client, onFinished: { finished = true })
        await recovery.start()
        await recovery.submit(pressing: Self.recoveryAction)
        guard case let .settings(settings) = recovery.state else {
            Issue.record("Expected recovery settings")
            return
        }

        // When the profile change is saved, including its verification when required
        await settings.start()
        await settings.submit(pressing: Self.profileAction)
        if requiresVerification {
            guard case let .verification(verification) = settings.state else {
                Issue.record("Expected address verification")
                return
            }
            await verification.start()
            await verification.submit(pressing: Self.recoveryAction)
            verification.finish()
        }
        recovery.finish()

        // Then recovery still requires a password change
        #expect(!finished)
        guard case .settings = recovery.state else {
            Issue.record("A profile save must not complete password recovery")
            return
        }
    }

    @Test("Rejected password changes keep recovery open", arguments: [false, true])
    func rejectedPasswordKeepsRecoveryOpen(reauthenticationRequired: Bool) async {
        // Given a password submission the backend rejects
        var finished = false
        let client = makeClient()
        await client.setSubmitSettingsFlowResult(reauthenticationRequired
            ? .failure(.reauthenticationRequired)
            : .success(.pending(Self.settingsFlow)))
        let recovery = RecoveryViewModel(client: client, onFinished: { finished = true })
        await recovery.start()
        await recovery.submit(pressing: Self.recoveryAction)
        guard case let .settings(settings) = recovery.state else {
            Issue.record("Expected recovery settings")
            return
        }

        // When the rejected password is submitted
        await settings.start()
        await settings.submit(pressing: Self.passwordAction)
        recovery.finish()

        // Then the form remains available and recovery cannot finish
        #expect(!finished)
        guard case .form = settings.state else {
            Issue.record("Expected the form to remain available after rejection")
            return
        }
        #expect((settings.reauthentication != nil) == reauthenticationRequired)
    }

    @Test("Retrying a failed settings fetch preserves the recovery handle")
    func retryLoadsTheSameFlow() async {
        // Given recovery settings could not be loaded
        let client = makeClient()
        await client.setGetSettingsFlowResult(.failure(.server(status: 503, id: nil, messages: [])))
        let recovery = RecoveryViewModel(client: client, onFinished: {})
        await recovery.start()
        await recovery.submit(pressing: Self.recoveryAction)
        guard case let .settings(settings) = recovery.state else {
            Issue.record("Expected recovery settings")
            return
        }
        await settings.start()
        guard case .failed = settings.state else {
            Issue.record("Expected the fetch error to be shown")
            return
        }

        // When the user retries after connectivity is restored
        await client.setGetSettingsFlowResult(.success(Self.settingsFlow))
        await settings.start()

        // Then the same flow is fetched, rather than creating a replacement
        #expect(await client.requestedSettingsFlowID == "recovery-settings-1")
        #expect(await client.getSettingsFlowCallCount == 2)
        #expect(await client.createSettingsFlowCallCount == 0)
        guard case let .form(flow) = settings.state else {
            Issue.record("Expected the recovered settings form")
            return
        }
        #expect(flow.id == "recovery-settings-1")
    }

    @Test("Recovery can finish directly when the backend skips settings")
    func recoveryWithoutSettings() async {
        // Given a project that does not require settings after recovery
        var finished = false
        let client = makeClient()
        await client.setSubmitRecoveryFlowResult(.success(.success(OryRecoveryResult(settings: nil))))
        let recovery = RecoveryViewModel(client: client, onFinished: { finished = true })

        // When recovery succeeds and the user continues
        await recovery.start()
        await recovery.submit(pressing: Self.recoveryAction)
        recovery.finish()

        // Then completion requires no settings request
        #expect(finished)
        #expect(await client.getSettingsFlowCallCount == 0)
        #expect(await client.createSettingsFlowCallCount == 0)
    }

    @Test("Ordinary account settings still create a new flow")
    func ordinarySettingsStartFresh() async {
        // Given settings opened independently of recovery
        let client = OryClientStub(createSettingsFlowResult: .success(Self.settingsFlow))
        let settings = SettingsViewModel(client: client)

        // When the screen starts
        await settings.start()

        // Then it creates a flow instead of fetching a recovery handle
        #expect(await client.createSettingsFlowCallCount == 1)
        #expect(await client.getSettingsFlowCallCount == 0)
        guard case .form = settings.state else {
            Issue.record("Expected the account settings form")
            return
        }
    }

    private func makeClient() -> OryClientStub {
        OryClientStub(
            createRecoveryFlowResult: .success(OryFlow(id: "recovery-1", kind: .recovery)),
            submitRecoveryFlowResult: .success(.success(OryRecoveryResult(
                settings: OrySettingsHandle(flowID: "recovery-settings-1")
            ))),
            getSettingsFlowResult: .success(Self.settingsFlow),
            submitSettingsFlowResult: .success(.success(Self.saved))
        )
    }
}
