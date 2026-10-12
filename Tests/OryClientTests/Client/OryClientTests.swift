import Foundation
import Testing
import OryClientTestDoubles
@testable import OryClient

@Suite("OryClient")
struct OryClientTests {

    @Test("currentSession without a stored token throws notAuthenticated and skips the network")
    func currentSessionNoToken() async throws {
        // Given a client with empty storage
        let frontend = FakeFrontendRepository()
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        // When / Then
        do {
            _ = try await client.currentSession()
            Issue.record("expected currentSession to throw")
        } catch let error as OryClientError {
            #expect(error.isNotAuthenticated)
        }

        // And the data source was never called
        let receivedToken = await frontend.receivedSessionToken
        #expect(receivedToken == nil)
    }

    @Test("currentSession passes the stored token and returns the mapped session")
    func currentSessionHappyPath() async throws {
        // Given a stored token and a data source returning a session
        let storage = InMemorySessionStorage(initialToken: "ory_st_abc")
        let frontend = FakeFrontendRepository(currentSession: .success(Sample.session()))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.currentSession()

        // Then
        #expect(result.id == "session-1")
        let receivedToken = await frontend.receivedSessionToken
        #expect(receivedToken == "ory_st_abc")
    }

    @Test("currentSession propagates sessionExpired from the data source")
    func currentSessionExpired() async throws {
        let storage = InMemorySessionStorage(initialToken: "expired")
        let frontend = FakeFrontendRepository(currentSession: .failure(.sessionExpired))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        do {
            _ = try await client.currentSession()
            Issue.record("expected currentSession to throw")
        } catch let error as OryClientError {
            #expect(error.isSessionExpired)
        }

        // And the rejected token is not kept at rest: the user is signed out, and the next
        // call says so instead of reporting an expired session forever.
        #expect(try await storage.sessionToken() == nil)
    }

    @Test("a second-factor demand keeps the token — it is still valid")
    func currentSessionSecondFactorKeepsToken() async throws {
        let storage = InMemorySessionStorage(initialToken: "aal1")
        let frontend = FakeFrontendRepository(currentSession: .failure(.secondFactorRequired))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        await #expect(throws: OryClientError.self) {
            _ = try await client.currentSession()
        }

        // Clearing here would make step-up impossible: it needs this very token.
        #expect(try await storage.sessionToken() == "aal1")
    }

    // MARK: - Logout

    @Test("logout revokes the session on the server and clears the stored token")
    func logoutRevokesAndClears() async throws {
        let storage = InMemorySessionStorage(initialToken: "ory_st_live")
        let frontend = FakeFrontendRepository(revokeSession: .success(()))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        try await client.logout()

        #expect(await frontend.receivedSessionToken == "ory_st_live")
        #expect(await frontend.submitCallCount == 1)
        #expect(try await storage.sessionToken() == nil)
    }

    @Test("logout with no stored token does nothing and skips the network")
    func logoutNoToken() async throws {
        let frontend = FakeFrontendRepository()
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        try await client.logout()

        #expect(await frontend.submitCallCount == 0)
    }

    @Test("logout treats an already-invalid token as an already-completed logout")
    func logoutAlreadyInvalid() async throws {
        let storage = InMemorySessionStorage(initialToken: "stale")
        let frontend = FakeFrontendRepository(revokeSession: .failure(.sessionExpired))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // A 401/403 (sessionExpired) is not surfaced as an error, and the token is still cleared.
        try await client.logout()

        #expect(try await storage.sessionToken() == nil)
    }

    @Test("logout clears the token then rethrows a genuine server failure")
    func logoutClearsThenThrowsOnServerFailure() async throws {
        let storage = InMemorySessionStorage(initialToken: "ory_st_live")
        let frontend = FakeFrontendRepository(revokeSession: .failure(.server(status: 500, id: nil, messages: [])))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        do {
            try await client.logout()
            Issue.record("expected logout to rethrow the server failure")
        } catch let error as OryClientError {
            #expect(error.serverStatus == 500)
        }
        // The local token is cleared regardless, so the user is signed out on this device.
        #expect(try await storage.sessionToken() == nil)
    }

    @Test("submitLoginFlow success stores the returned token and returns the session")
    func submitStoresToken() async throws {
        // Given
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(
            submitLogin: .success(.success(session: Sample.session(), token: "ory_st_new"))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.submitLoginFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        // Then
        guard case let .success(authenticated) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(authenticated.session.id == "session-1")
        let stored = try await storage.sessionToken()
        #expect(stored == "ory_st_new")
    }

    @Test("submitLoginFlow pending returns the next flow and stores nothing")
    func submitPending() async throws {
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(submitLogin: .success(.pending(Sample.loginFlow(id: "flow-2"))))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitLoginFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .pending(pendingFlow) = result else {
            Issue.record("expected pending, got \(result)")
            return
        }
        #expect(pendingFlow.id == "flow-2")
        let stored = try await storage.sessionToken()
        #expect(stored == nil)
    }

    @Test("createRegistrationFlow delegates to the data source")
    func createRegistration() async throws {
        let frontend = FakeFrontendRepository(createRegistrationFlow: .success(Sample.loginFlow(id: "reg-1")))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        let flow = try await client.createRegistrationFlow()

        #expect(flow.id == "reg-1")
    }

    @Test("submitRegistrationFlow with a session stores the token and returns the identity")
    func submitRegistrationWithSession() async throws {
        // Given the project signs the user in after registration
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(
            submitRegistration: .success(.success(identity: Sample.identity(), session: Sample.session(), token: "ory_st_reg", verification: nil))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.submitRegistrationFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        // Then the session is returned and its token stored
        guard case let .success(registration) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(registration.identity.id == "identity-1")
        #expect(registration.session != nil)
        let stored = try await storage.sessionToken()
        #expect(stored == "ory_st_reg")
    }

    @Test("submitRegistrationFlow without a session returns the identity only and stores nothing")
    func submitRegistrationWithoutSession() async throws {
        // Given the project requires verification before sign-in (no session, no token)
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(
            submitRegistration: .success(.success(identity: Sample.identity(id: "id-2"), session: nil, token: nil, verification: nil))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.submitRegistrationFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        // Then no session, and nothing stored
        guard case let .success(registration) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(registration.identity.id == "id-2")
        #expect(registration.session == nil)
        let stored = try await storage.sessionToken()
        #expect(stored == nil)
    }

    @Test("submitRegistrationFlow pending returns the next flow")
    func submitRegistrationPending() async throws {
        let frontend = FakeFrontendRepository(submitRegistration: .success(.pending(Sample.loginFlow(id: "reg-2"))))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitRegistrationFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .pending(flow) = result else {
            Issue.record("expected pending, got \(result)")
            return
        }
        #expect(flow.id == "reg-2")
    }

    @Test("submitRegistrationFlow surfaces the verification handle when there is no session")
    func submitRegistrationSurfacesVerification() async throws {
        let handle = OryVerificationHandle(flowID: "ver-99", address: "a@b.com")
        let frontend = FakeFrontendRepository(
            submitRegistration: .success(.success(identity: Sample.identity(), session: nil, token: nil, verification: handle))
        )
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitRegistrationFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .success(registration) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(registration.session == nil)
        #expect(registration.verification?.flowID == "ver-99")
        #expect(registration.verification?.address == "a@b.com")
    }

    @Test("createVerificationFlow and getVerificationFlow delegate to the data source")
    func verificationFlowCreationAndFetch() async throws {
        let frontend = FakeFrontendRepository(
            createVerificationFlow: .success(Sample.flow(id: "ver-create", kind: .verification)),
            getVerificationFlow: .success(Sample.flow(id: "ver-get", kind: .verification))
        )
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        let created = try await client.createVerificationFlow()
        let fetched = try await client.getVerificationFlow(id: "any")

        #expect(created.id == "ver-create")
        #expect(fetched.id == "ver-get")
    }

    @Test("submitVerificationFlow maps completed to success and pending to re-render")
    func submitVerificationOutcomes() async throws {
        // Completed
        let completedFrontend = FakeFrontendRepository(submitVerification: .success(.completed))
        let completedClient = OryClient(storage: InMemorySessionStorage(), frontend: completedFrontend, deviceAuthn: completedFrontend)
        let completed = try await completedClient.submitVerificationFlow(Sample.flow(kind: .verification), values: OryFormValues(), pressing: Sample.submitAction())
        guard case .success = completed else {
            Issue.record("expected success, got \(completed)")
            return
        }

        // Pending
        let pendingFrontend = FakeFrontendRepository(submitVerification: .success(.pending(Sample.flow(id: "ver-next", kind: .verification))))
        let pendingClient = OryClient(storage: InMemorySessionStorage(), frontend: pendingFrontend, deviceAuthn: pendingFrontend)
        let pending = try await pendingClient.submitVerificationFlow(Sample.flow(kind: .verification), values: OryFormValues(), pressing: Sample.submitAction())
        guard case let .pending(flow) = pending else {
            Issue.record("expected pending, got \(pending)")
            return
        }
        #expect(flow.id == "ver-next")
    }

    // MARK: - Recovery

    @Test("createRecoveryFlow delegates to the data source")
    func createRecovery() async throws {
        let frontend = FakeFrontendRepository(createRecoveryFlow: .success(Sample.flow(id: "rec-1", kind: .recovery)))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        let flow = try await client.createRecoveryFlow()

        #expect(flow.id == "rec-1")
    }

    @Test("submitRecoveryFlow success stores the privileged token and surfaces the settings handle")
    func submitRecoverySuccess() async throws {
        // Given recovery passed and the server issued a privileged session plus a settings flow
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(
            submitRecovery: .success(.completed(token: "ory_st_rec", settingsFlowID: "set-1"))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.submitRecoveryFlow(Sample.flow(kind: .recovery), values: OryFormValues(), pressing: Sample.submitAction())

        // Then the settings handle is surfaced and the privileged token is stored
        guard case let .success(recovery) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(recovery.settings?.flowID == "set-1")
        #expect(try await storage.sessionToken() == "ory_st_rec")
    }

    @Test("submitRecoveryFlow success without a settings step stores the token and has no handle")
    func submitRecoverySuccessNoSettings() async throws {
        // Given the project skips the settings step after recovery
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(
            submitRecovery: .success(.completed(token: "ory_st_rec", settingsFlowID: nil))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitRecoveryFlow(Sample.flow(kind: .recovery), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .success(recovery) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(recovery.settings == nil)
        #expect(try await storage.sessionToken() == "ory_st_rec")
    }

    @Test("submitRecoveryFlow pending returns the next flow and stores nothing")
    func submitRecoveryPending() async throws {
        let storage = InMemorySessionStorage()
        let frontend = FakeFrontendRepository(submitRecovery: .success(.pending(Sample.flow(id: "rec-2", kind: .recovery))))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitRecoveryFlow(Sample.flow(kind: .recovery), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .pending(flow) = result else {
            Issue.record("expected pending, got \(result)")
            return
        }
        #expect(flow.id == "rec-2")
        #expect(try await storage.sessionToken() == nil)
    }

    // MARK: - Settings

    @Test("createSettingsFlow without a stored token throws notAuthenticated and skips the network")
    func createSettingsNoToken() async throws {
        let frontend = FakeFrontendRepository()
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        do {
            _ = try await client.createSettingsFlow()
            Issue.record("expected createSettingsFlow to throw")
        } catch let error as OryClientError {
            #expect(error.isNotAuthenticated)
        }

        #expect(await frontend.receivedSessionToken == nil)
    }

    @Test("createSettingsFlow passes the stored token and returns the flow")
    func createSettings() async throws {
        let storage = InMemorySessionStorage(initialToken: "tok")
        let frontend = FakeFrontendRepository(createSettingsFlow: .success(Sample.flow(id: "set-1", kind: .settings)))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let flow = try await client.createSettingsFlow()

        #expect(flow.id == "set-1")
        #expect(await frontend.receivedSessionToken == "tok")
    }

    @Test("getSettingsFlow passes the stored token and returns the flow (for a recovery handle)")
    func getSettings() async throws {
        let storage = InMemorySessionStorage(initialToken: "tok")
        let frontend = FakeFrontendRepository(getSettingsFlow: .success(Sample.flow(id: "set-get", kind: .settings)))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let flow = try await client.getSettingsFlow(id: "settings-77")

        #expect(flow.id == "set-get")
        #expect(await frontend.receivedSessionToken == "tok")
    }

    @Test("submitSettingsFlow success returns the updated identity")
    func submitSettingsSuccess() async throws {
        let storage = InMemorySessionStorage(initialToken: "tok")
        let frontend = FakeFrontendRepository(submitSettings: .success(.completed(Sample.identity(id: "id-9"))))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitSettingsFlow(Sample.flow(kind: .settings), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .success(settings) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(settings.identity.id == "id-9")
        #expect(settings.verification == nil)
    }

    @Test("submitSettingsFlow hands off to verification even when the state reflects a previous save", arguments: ["show_form", "success"])
    func submitSettingsVerification(state: String) async throws {
        // Given the verify_new_address hook response, with an unknown continuation before verification
        var payload = try #require(try JSONSerialization.jsonObject(with: Fixture.settingsFlowVerification) as? [String: Any])
        payload["state"] = state
        let network = MockHTTPClient(data: try JSONSerialization.data(withJSONObject: payload), statusCode: 200)
        let frontend = LiveFrontendRepository(gateway: FrontendGateway(client: network))
        let storage = InMemorySessionStorage(initialToken: "tok")
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: FakeFrontendRepository())

        // When
        let result = try await client.submitSettingsFlow(Sample.flow(kind: .settings), values: OryFormValues(), pressing: Sample.submitAction())

        // Then the settings submission hands off instead of asking to submit the profile again
        guard case let .success(settings) = result else {
            Issue.record("expected verification handoff, got \(result)")
            return
        }
        #expect(settings.identity.id == "identity-1")
        #expect(settings.verification?.flowID == "verification-77")
        #expect(settings.verification?.address == "updated@example.com")
        let traits = try settings.identity.decodeTraits(as: [String: String].self)
        #expect(traits["email"] == "user@example.com")
        #expect(try await storage.sessionToken() == "tok")
    }

    @Test("submitSettingsFlow pending returns the next flow")
    func submitSettingsPending() async throws {
        let storage = InMemorySessionStorage(initialToken: "tok")
        let frontend = FakeFrontendRepository(submitSettings: .success(.pending(Sample.flow(id: "set-2", kind: .settings))))
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        let result = try await client.submitSettingsFlow(Sample.flow(kind: .settings), values: OryFormValues(), pressing: Sample.submitAction())

        guard case let .pending(flow) = result else {
            Issue.record("expected pending, got \(result)")
            return
        }
        #expect(flow.id == "set-2")
    }
}
