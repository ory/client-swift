import OryClient
import OryClientTestDoubles
import Testing
@testable import OryClientExample

/// Routing tests for the example's view models. They drive each view model with
/// `OryClientStub` — the same test double an integrator would use — and assert which
/// navigation callback fires. This doubles as documentation of the intended behavior.
@MainActor
struct OryClientExampleTests {

    // MARK: - Login

    @Test("Login reports the session on success")
    func loginSuccessReportsSession() async {
        var signedIn: OrySession?
        let stub = OryClientStub(
            createLoginFlowResult: .success(Fixtures.flow(.login)),
            submitLoginFlowResult: .success(.success(OryAuthenticatedSession(session: Fixtures.session())))
        )
        let viewModel = LoginViewModel(client: stub, onSignedIn: { signedIn = $0 }, onForgotPassword: {}, onDismiss: {})

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(signedIn?.id == "session-1")
    }

    @Test("Login surfaces an error message on failure")
    func loginFailureShowsError() async {
        let stub = OryClientStub(
            createLoginFlowResult: .success(Fixtures.flow(.login)),
            submitLoginFlowResult: .failure(.server(status: 400, id: nil, messages: [Fixtures.errorMessage]))
        )
        let viewModel = LoginViewModel(client: stub, onSignedIn: { _ in }, onForgotPassword: {}, onDismiss: {})

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(viewModel.submitError != nil)
    }

    @Test("An expired login continues with the replacement flow")
    func loginExpiredContinuesWithReplacement() async {
        let stub = OryClientStub(
            createLoginFlowResult: .success(Fixtures.flow(.login)),
            getLoginFlowResult: .success(OryFlow(id: "replacement", kind: .login, actions: [Fixtures.submitAction])),
            submitLoginFlowResult: Fixtures.expired
        )
        let viewModel = LoginViewModel(client: stub, onSignedIn: { _ in }, onForgotPassword: {}, onDismiss: {})
        await viewModel.start()

        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(await stub.requestedLoginFlowID == "replacement")
        #expect(viewModel.state.flowID == "replacement")
        #expect(await stub.createLoginFlowCallCount == 1)
    }

    @Test("An expired re-authentication starts over, because the replacement is not a refresh")
    func loginExpiredRefreshStartsOver() async {
        let options = OryLoginFlowOptions(refresh: true, aal: .aal2)
        let stub = OryClientStub(
            createLoginFlowResult: .success(
                OryFlow(id: "flow-1", kind: .login, actions: [Fixtures.submitAction], requestedAAL: .aal2, isRefresh: true)
            ),
            getLoginFlowResult: .success(
                OryFlow(id: "replacement", kind: .login, actions: [Fixtures.submitAction], requestedAAL: .aal2)
            ),
            submitLoginFlowResult: Fixtures.expired
        )
        let viewModel = LoginViewModel(client: stub, options: options, onSignedIn: { _ in }, onForgotPassword: {}, onDismiss: {})
        await viewModel.start()

        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(await stub.createLoginFlowCallCount == 2)
        #expect(await stub.requestedLoginFlowOptions == options)
        #expect(viewModel.state.flowID == "flow-1")
    }

    @Test("An expired login starts over when fetching the replacement fails")
    func loginExpiredReplacementFailureStartsOver() async {
        let stub = OryClientStub(
            createLoginFlowResult: .success(Fixtures.flow(.login)),
            submitLoginFlowResult: Fixtures.expired
        )
        let viewModel = LoginViewModel(client: stub, onSignedIn: { _ in }, onForgotPassword: {}, onDismiss: {})
        await viewModel.start()

        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(await stub.createLoginFlowCallCount == 2)
        #expect(viewModel.state.flowID == "flow-1")
    }

    // MARK: - Registration

    @Test("Registration with a session signs the user in")
    func registrationSessionSignsIn() async {
        var signedIn: OrySession?
        let stub = registrationStub(
            outcome: OryRegistrationResult(
                identity: Fixtures.identity,
                session: OryAuthenticatedSession(session: Fixtures.session()),
                verification: nil
            )
        )
        let viewModel = makeRegistrationViewModel(client: stub, onSignedIn: { signedIn = $0 })

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(signedIn != nil)
    }

    @Test("Registration hands off to verification when required")
    func registrationRequiresVerification() async {
        var handle: OryVerificationHandle?
        let stub = registrationStub(
            outcome: OryRegistrationResult(
                identity: Fixtures.identity,
                session: nil,
                verification: OryVerificationHandle(flowID: "verify-1", address: "user@example.com")
            )
        )
        let viewModel = makeRegistrationViewModel(client: stub, onVerificationNeeded: { handle = $0 })

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(handle?.flowID == "verify-1")
    }

    @Test("Registration reports account-created when there is no session or verification")
    func registrationAccountCreated() async {
        var accountCreated = false
        let stub = registrationStub(
            outcome: OryRegistrationResult(identity: Fixtures.identity, session: nil, verification: nil)
        )
        let viewModel = makeRegistrationViewModel(client: stub, onAccountCreated: { accountCreated = true })

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(accountCreated)
    }

    @Test("Registration re-renders on a pending flow without navigating")
    func registrationPendingReRenders() async {
        var navigated = false
        let stub = OryClientStub(
            createRegistrationFlowResult: .success(Fixtures.flow(.registration)),
            submitRegistrationFlowResult: .success(.pending(Fixtures.flow(.registration)))
        )
        let viewModel = RegistrationViewModel(
            client: stub,
            onSignedIn: { _ in navigated = true },
            onVerificationNeeded: { _ in navigated = true },
            onAccountCreated: { navigated = true },
            onDismiss: {}
        )

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)

        #expect(!navigated)
        #expect(viewModel.state.isForm)
    }

    // MARK: - Verification

    @Test("Verification moves to verified, then continues on finish")
    func verificationSuccessContinues() async {
        var continued = false
        let stub = OryClientStub(
            getVerificationFlowResult: .success(Fixtures.flow(.verification)),
            submitVerificationFlowResult: .success(.success(OryVerificationResult()))
        )
        let viewModel = VerificationViewModel(client: stub, existingFlowID: "verify-1", onVerified: { continued = true })

        await viewModel.start()
        await viewModel.submit(pressing: Fixtures.submitAction)
        #expect(viewModel.state.isVerified)

        viewModel.finish()
        #expect(continued)
    }

    // MARK: - Root

    @Test("Root starts signed in when a session is stored")
    func rootStartsSignedIn() async {
        let stub = OryClientStub(currentSessionResult: .success(Fixtures.session()))
        let viewModel = RootViewModel(client: stub)

        await viewModel.onTask()

        #expect(viewModel.state.isSignedIn)
    }

    @Test("Root starts signed out when there is no session")
    func rootStartsSignedOut() async {
        let stub = OryClientStub(currentSessionResult: .failure(.notAuthenticated))
        let viewModel = RootViewModel(client: stub)

        await viewModel.onTask()

        #expect(viewModel.state.isSignedOut)
    }

    @Test("Sign out logs out through the client and returns to the signed-out journey")
    func signOutLogsOut() async {
        let stub = OryClientStub()
        let viewModel = RootViewModel(client: stub)

        await viewModel.signOut()

        #expect(await stub.logoutCallCount == 1)
        #expect(viewModel.state.isSignedOut)
    }

    // MARK: - Helpers

    private func registrationStub(outcome: OryRegistrationResult) -> OryClientStub {
        OryClientStub(
            createRegistrationFlowResult: .success(Fixtures.flow(.registration)),
            submitRegistrationFlowResult: .success(.success(outcome))
        )
    }

    private func makeRegistrationViewModel(
        client: OryClientProtocol,
        onSignedIn: @escaping (OrySession) -> Void = { _ in },
        onVerificationNeeded: @escaping (OryVerificationHandle) -> Void = { _ in },
        onAccountCreated: @escaping () -> Void = {}
    ) -> RegistrationViewModel {
        RegistrationViewModel(
            client: client,
            onSignedIn: onSignedIn,
            onVerificationNeeded: onVerificationNeeded,
            onAccountCreated: onAccountCreated,
            onDismiss: {}
        )
    }
}

// MARK: - Fixtures

private enum Fixtures {

    static let submitAction = OryInputField(name: .method, kind: .submit, value: "password")

    static let identity = OryIdentity(id: "identity-1", schemaID: "default")

    static let errorMessage = OryUIMessage(id: 4_000_006, text: "The credentials are invalid.", kind: .error)

    static let expired: Result<OryFlowResult<OryAuthenticatedSession>, OryClientError> =
        .failure(.flowExpired(replacementFlowID: "replacement"))

    static func session(id: String = "session-1") -> OrySession {
        OrySession(
            id: id,
            isActive: true,
            expiresAt: nil,
            authenticatedAt: nil,
            authenticatorAssuranceLevel: .aal1,
            identity: nil
        )
    }

    static func flow(_ kind: OryFlowKind) -> OryFlow {
        OryFlow(id: "flow-1", kind: kind, actions: [submitAction])
    }
}

// MARK: - State matchers

private extension LoginViewModel.State {
    var isForm: Bool { if case .form = self { true } else { false } }
    var flowID: String? { if case let .form(flow) = self { flow.id } else { nil } }
}

private extension RegistrationViewModel.State {
    var isForm: Bool { if case .form = self { true } else { false } }
}

private extension VerificationViewModel.State {
    var isVerified: Bool { if case .verified = self { true } else { false } }
}

private extension RootViewModel.State {
    var isSignedIn: Bool { if case .signedIn = self { true } else { false } }
    var isSignedOut: Bool { if case .signedOut = self { true } else { false } }
}
