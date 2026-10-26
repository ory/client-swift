import Foundation
import Testing
@testable import OryClient

@Suite("LiveFrontendRepository")
struct LiveFrontendRepositoryTests {

    private func makeDataSource(data: Data, status: Int) -> (LiveFrontendRepository, MockHTTPClient) {
        let network = MockHTTPClient(data: data, statusCode: status)
        let dataSource = LiveFrontendRepository(gateway: FrontendGateway(client: network))
        return (dataSource, network)
    }

    @Test("currentSession decodes and maps a 200 session, and sends the token to whoami")
    func currentSession200() async throws {
        // Given a 200 whoami response
        let (dataSource, network) = makeDataSource(data: Fixture.session, status: 200)

        // When
        let session = try await dataSource.currentSession(sessionToken: "tok")

        // Then the DTO is collapsed into the domain model
        #expect(session.id == "session-1")
        #expect(session.isActive)
        #expect(session.authenticatorAssuranceLevel == .aal2)
        #expect(session.identity?.id == "identity-1")

        // And the request carried the token to the right endpoint
        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
        #expect(request?.url.absoluteString == "https://example.com/sessions/whoami")
    }

    @Test("currentSession tolerates an unknown assurance level instead of throwing")
    func currentSessionUnknownAAL() async throws {
        // Given a session whose AAL value this build does not know
        let (dataSource, _) = makeDataSource(data: Fixture.sessionUnknownAAL, status: 200)

        // When / Then it decodes and maps to .unknown rather than failing
        let session = try await dataSource.currentSession(sessionToken: "tok")
        #expect(session.authenticatorAssuranceLevel == .unknown)
    }

    @Test("currentSession maps 401 to sessionExpired")
    func currentSession401() async throws {
        let (dataSource, _) = makeDataSource(data: Data("{}".utf8), status: 401)

        do {
            _ = try await dataSource.currentSession(sessionToken: "tok")
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            #expect(error.isSessionExpired)
        }
    }

    @Test("createLoginFlow renders inputs and actions, and hides hidden fields")
    func createLoginFlow() async throws {
        // Given a password login flow
        let (dataSource, _) = makeDataSource(data: Fixture.loginFlow, status: 200)

        // When
        let flow = try await dataSource.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then identifier and password are renderable inputs
        #expect(flow.id == "login-1")
        let inputNames = flow.nodes.compactMap { node -> OryFieldName? in
            if case let .input(field) = node.content { return field.name } else { return nil }
        }
        #expect(inputNames.contains(.identifier))
        #expect(inputNames.contains(.password))

        // And the hidden csrf token is not rendered, but the submit is offered as an action
        #expect(!inputNames.contains(.csrfToken))
        #expect(flow.actions.contains { $0.value == "password" })
    }

    @Test("createLoginFlow keeps the server's group name")
    func createLoginFlowKnownGroup() async throws {
        // Given
        let (dataSource, _) = makeDataSource(data: Fixture.loginFlow, status: 200)

        // When
        let flow = try await dataSource.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then
        let password = flow.nodes.first { $0.id == "password" }
        #expect(password?.group == .password)
        #expect(password?.group.rawValue == "password")
    }

    @Test("createLoginFlow keeps group, input type, autocomplete, and message type values this build does not know")
    func createLoginFlowUnknownValues() async throws {
        // Given a flow whose values all come from a backend newer than this build
        let (dataSource, _) = makeDataSource(data: Fixture.loginFlowUnknownValues, status: 200)

        // When
        let flow = try await dataSource.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then each value keeps the wire string, so an app can match it without a client update
        let node = try #require(flow.nodes.first { $0.id == "future_field" })
        guard case let .input(field) = node.content else {
            Issue.record("expected an input node, got \(node.content)")
            return
        }
        #expect(node.group == OryNodeGroup(rawValue: "future_method"))
        #expect(field.kind == OryInputField.Kind(rawValue: "future_input_type"))
        #expect(field.autocomplete == OryInputField.Autocomplete(rawValue: "future-hint"))
        #expect(flow.messages.map(\.kind) == [OryUIMessage.Kind(rawValue: "future_message_type")])
    }

    @Test("createLoginFlow tolerates a node type this build does not know")
    func createLoginFlowUnknownNodeType() async throws {
        // Ory adds node types over time (`div` in 2025). An app built before one exists must
        // keep working: the unknown node is dropped, never the whole flow.
        let (dataSource, _) = makeDataSource(data: Fixture.loginFlowUnknownNodeType, status: 200)

        let flow = try await dataSource.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        #expect(flow.nodes.contains { node in
            if case let .input(field) = node.content { return field.name == .identifier }
            return false
        })
    }

    @Test("submitLogin tolerates an unknown continue_with action and still returns the token")
    func submitLoginUnknownContinueWith() async throws {
        // The session already exists by the time `continue_with` is read, so failing to decode
        // an action this build does not know would throw away a token the user has earned.
        let (dataSource, _) = makeDataSource(data: Fixture.successfulLoginUnknownContinueWith, status: 200)

        let outcome = try await dataSource.submitLogin(
            url: URL(string: "https://example.com/self-service/login?flow=x")!,
            fields: ["method": "password"],
            sessionToken: nil
        )

        guard case let .success(_, token) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(token == "ory_st_unknown_continue_with")
    }

    @Test("submitRegistration still finds the verification handle past an unknown action")
    func submitRegistrationUnknownContinueWith() async throws {
        // An unknown action must not shadow the known one behind it in the array.
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistrationUnknownContinueWith, status: 200)

        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/self-service/registration?flow=x")!,
            fields: ["method": "password"],
            sessionToken: nil
        )

        guard case let .success(_, _, _, verification) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(verification?.flowID == "verification-100")
    }

    @Test("submitLogin returns success with the token on 200 and posts to the action URL")
    func submitSuccess() async throws {
        let (dataSource, network) = makeDataSource(data: Fixture.successfulLogin, status: 200)
        let actionURL = URL(string: "https://example.com/self-service/login?flow=x")!

        let outcome = try await dataSource.submitLogin(url: actionURL, fields: ["method": "password"], sessionToken: nil)

        guard case let .success(session, token) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(session.id == "session-1")
        #expect(token == "ory_st_test")

        let request = await network.lastRequest
        #expect(request?.method == .post)
        #expect(request?.url == actionURL)
    }

    @Test("submitLogin returns pending on 400")
    func submitPending() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.loginFlow, status: 400)

        let outcome = try await dataSource.submitLogin(
            url: URL(string: "https://example.com/login")!,
            fields: [:],
            sessionToken: nil
        )

        guard case let .pending(flow) = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
        #expect(flow.id == "login-1")
    }

    @Test("createRegistrationFlow renders trait and password fields, hides hidden fields")
    func createRegistrationFlow() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.registrationFlow, status: 200)

        let flow = try await dataSource.createRegistrationFlow()

        #expect(flow.kind == .registration)
        let inputNames = flow.nodes.compactMap { node -> OryFieldName? in
            if case let .input(field) = node.content { return field.name } else { return nil }
        }
        // The schema-defined trait renders as a dynamic custom field.
        #expect(inputNames.contains(OryFieldName(rawValue: "traits.email")))
        #expect(inputNames.contains(.password))
        #expect(!inputNames.contains(.csrfToken))
        #expect(flow.actions.contains { $0.value == "password" })
    }

    @Test("submitRegistration returns identity, session, and token on 200")
    func submitRegistrationWithSession() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistration, status: 200)

        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
        )

        guard case let .success(identity, session, token, _) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(identity.id == "identity-1")
        #expect(session?.id == "session-9")
        #expect(token == "ory_st_reg")
    }

    @Test("submitRegistration returns the identity only when there is no session")
    func submitRegistrationWithoutSession() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistrationNoSession, status: 200)

        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
        )

        guard case let .success(identity, session, token, _) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(identity.id == "identity-2")
        #expect(session == nil)
        #expect(token == nil)
    }

    @Test("submitRegistration takes the identity from the session when the response omits it")
    func submitRegistrationIdentityInSession() async throws {
        // Given a 200 without a top-level identity, whose session carries one
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistrationIdentityInSession, status: 200)

        // When
        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
        )

        // Then
        guard case let .success(identity, session, token, _) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(identity.id == "identity-3")
        #expect(session?.id == "session-10")
        #expect(token == "ory_st_reg")
    }

    @Test("submitRegistration throws unexpectedResponse when no identity is returned at all")
    func submitRegistrationNoIdentity() async throws {
        // Given a 200 with neither an identity nor a session that carries one
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistrationNoIdentity, status: 200)

        // When / Then
        do {
            _ = try await dataSource.submitRegistration(
                url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
            )
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected unexpectedResponse, got \(error)")
                return
            }
        }
    }

    @Test("submitRegistration returns pending on 400")
    func submitRegistrationPending() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.registrationFlow, status: 400)

        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
        )

        guard case let .pending(flow) = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
        #expect(flow.id == "registration-1")
    }

    // MARK: - Verification

    @Test("createVerificationFlow renders the verification flow")
    func createVerificationFlow() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.verificationFlow, status: 200)

        let flow = try await dataSource.createVerificationFlow()

        #expect(flow.kind == .verification)
        #expect(flow.actions.contains { $0.value == "code" })
    }

    @Test("getVerificationFlow fetches by id via the id query parameter")
    func getVerificationFlow() async throws {
        let (dataSource, network) = makeDataSource(data: Fixture.verificationFlow, status: 200)

        let flow = try await dataSource.getVerificationFlow(id: "verification-99")

        #expect(flow.kind == .verification)
        let request = await network.lastRequest
        #expect(request?.url.absoluteString.contains("/self-service/verification/flows?id=verification-99") == true)
    }

    @Test("submitVerification is pending until the flow passes the challenge")
    func submitVerificationPending() async throws {
        // Given a flow still in the choose_method state
        let (dataSource, _) = makeDataSource(data: Fixture.verificationFlow, status: 200)

        let outcome = try await dataSource.submitVerification(url: URL(string: "https://example.com/v")!, fields: [:])

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    @Test("submitVerification completes when the flow reaches passed_challenge")
    func submitVerificationCompleted() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.verificationFlowVerified, status: 200)

        let outcome = try await dataSource.submitVerification(url: URL(string: "https://example.com/v")!, fields: [:])

        guard case .completed = outcome else {
            Issue.record("expected completed, got \(outcome)")
            return
        }
    }

    @Test("submitVerification returns pending on 400 (validation)")
    func submitVerification400() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.verificationFlow, status: 400)

        let outcome = try await dataSource.submitVerification(url: URL(string: "https://example.com/v")!, fields: [:])

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    @Test("submitRegistration surfaces the verification continue_with as a handle")
    func submitRegistrationVerificationHandle() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.successfulRegistrationVerification, status: 200)

        let outcome = try await dataSource.submitRegistration(
            url: URL(string: "https://example.com/registration")!, fields: [:], sessionToken: nil
        )

        guard case let .success(_, session, _, verification) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(session == nil)
        #expect(verification?.flowID == "verification-99")
        #expect(verification?.address == "verify@example.com")
    }

    // MARK: - Recovery

    @Test("createRecoveryFlow renders the recovery flow and requests the native endpoint")
    func createRecoveryFlow() async throws {
        let (dataSource, network) = makeDataSource(data: Fixture.recoveryFlow, status: 200)

        let flow = try await dataSource.createRecoveryFlow()

        #expect(flow.kind == .recovery)
        #expect(flow.actions.contains { $0.value == "code" })
        let request = await network.lastRequest
        #expect(request?.url.absoluteString.contains("/self-service/recovery/api") == true)
    }

    @Test("submitRecovery is pending until the flow passes the challenge")
    func submitRecoveryPending() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.recoveryFlow, status: 200)

        let outcome = try await dataSource.submitRecovery(url: URL(string: "https://example.com/r")!, fields: [:])

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    @Test("submitRecovery completes with the session token and settings flow on passed_challenge")
    func submitRecoveryCompleted() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.recoveryPassedChallenge, status: 200)

        let outcome = try await dataSource.submitRecovery(url: URL(string: "https://example.com/r")!, fields: [:])

        guard case let .completed(token, settingsFlowID) = outcome else {
            Issue.record("expected completed, got \(outcome)")
            return
        }
        #expect(token == "ory_st_recovered")
        #expect(settingsFlowID == "settings-77")
    }

    @Test("submitRecovery still finds the token and settings past an unknown continue_with")
    func submitRecoveryUnknownContinueWith() async throws {
        // An unknown action must not shadow the known ones behind it in the array.
        let (dataSource, _) = makeDataSource(data: Fixture.recoveryPassedChallengeUnknownContinueWith, status: 200)

        let outcome = try await dataSource.submitRecovery(url: URL(string: "https://example.com/r")!, fields: [:])

        guard case let .completed(token, settingsFlowID) = outcome else {
            Issue.record("expected completed, got \(outcome)")
            return
        }
        #expect(token == "ory_st_recovered")
        #expect(settingsFlowID == "settings-77")
    }

    @Test("submitRecovery returns pending on 400 (validation)")
    func submitRecovery400() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.recoveryFlow, status: 400)

        let outcome = try await dataSource.submitRecovery(url: URL(string: "https://example.com/r")!, fields: [:])

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    // MARK: - Settings

    @Test("createSettingsFlow renders the flow and carries the session token to the native endpoint")
    func createSettingsFlow() async throws {
        let (dataSource, network) = makeDataSource(data: Fixture.settingsFlow, status: 200)

        let flow = try await dataSource.createSettingsFlow(sessionToken: "tok")

        #expect(flow.kind == .settings)
        let inputNames = flow.nodes.compactMap { node -> OryFieldName? in
            if case let .input(field) = node.content { return field.name } else { return nil }
        }
        #expect(inputNames.contains(.password))
        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
        #expect(request?.url.absoluteString.contains("/self-service/settings/api") == true)
    }

    @Test("getSettingsFlow fetches by id via the id query parameter and carries the token")
    func getSettingsFlow() async throws {
        let (dataSource, network) = makeDataSource(data: Fixture.settingsFlow, status: 200)

        let flow = try await dataSource.getSettingsFlow(id: "settings-1", sessionToken: "tok")

        #expect(flow.kind == .settings)
        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
        #expect(request?.url.absoluteString.contains("/self-service/settings/flows?id=settings-1") == true)
    }

    @Test("submitSettings is pending while the flow is still showing the form")
    func submitSettingsPending() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.settingsFlow, status: 200)

        let outcome = try await dataSource.submitSettings(url: URL(string: "https://example.com/s")!, fields: [:], sessionToken: "tok")

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    @Test("submitSettings completes with the updated identity when the change is saved")
    func submitSettingsCompleted() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.settingsFlowSuccess, status: 200)

        let outcome = try await dataSource.submitSettings(url: URL(string: "https://example.com/s")!, fields: [:], sessionToken: "tok")

        guard case let .completed(identity, verification) = outcome else {
            Issue.record("expected completed, got \(outcome)")
            return
        }
        #expect(identity.id == "identity-1")
        #expect(verification == nil)
    }

    @Test("submitSettings returns pending on 400 (validation)")
    func submitSettings400() async throws {
        let (dataSource, _) = makeDataSource(data: Fixture.settingsFlow, status: 400)

        let outcome = try await dataSource.submitSettings(url: URL(string: "https://example.com/s")!, fields: [:], sessionToken: "tok")

        guard case .pending = outcome else {
            Issue.record("expected pending, got \(outcome)")
            return
        }
    }

    @Test("submitSettings preserves validation errors on 400 even after a previous successful save")
    func submitSettings400AfterSuccess() async throws {
        // Given a reused flow whose state still reflects the previous successful save
        let (dataSource, _) = makeDataSource(data: Fixture.settingsFlowValidationAfterSuccess, status: 400)

        // When the next submission is rejected
        let outcome = try await dataSource.submitSettings(url: URL(string: "https://example.com/s")!, fields: [:], sessionToken: "tok")

        // Then the caller receives the errors instead of a false success
        guard case let .pending(flow) = outcome else {
            Issue.record("expected validation flow, got \(outcome)")
            return
        }
        #expect(flow.messages.contains { $0.text == "The password is too short." })
    }

    @Test("submitSettings maps a privileged-session demand to reauthenticationRequired")
    func submitSettingsPrivileged() async throws {
        // A change to sensitive fields on a stale session returns session_refresh_required.
        let (dataSource, _) = makeDataSource(data: Fixture.settingsPrivilegedError, status: 403)

        do {
            _ = try await dataSource.submitSettings(url: URL(string: "https://example.com/s")!, fields: [:], sessionToken: "tok")
            Issue.record("expected submitSettings to throw")
        } catch let error as OryClientError {
            #expect(error.isReauthenticationRequired)
        }
    }
}
