import Foundation
import Testing
@testable import Ory

@Suite("Equatable and Hashable models")
struct EquatableModelsTests {

    private func mappedLoginFlow() async throws -> OryFlow {
        let network = MockHTTPClient(data: Fixture.loginFlow, statusCode: 200)
        let repository = LiveFrontendRepository(gateway: FrontendGateway(client: network))
        return try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)
    }

    @Test("Given the same server response mapped twice, when the flows are compared, then they are equal and hash the same")
    func flowsFromSameResponseAreEqual() async throws {
        let first = try await mappedLoginFlow()
        let second = try await mappedLoginFlow()

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("Given flows with the same id but a different step, when they are compared, then they differ")
    func flowsWithDifferentContentDiffer() {
        let first = OryFlow(id: "flow-1", kind: .login, state: .chooseMethod)
        let second = OryFlow(id: "flow-1", kind: .login, state: .sentEmail)

        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    @Test("Given flows with different hidden values, when they are compared, then they differ")
    func hiddenValuesTakePart() {
        let action = URL(string: "https://example.com/self-service/login?flow=1")!
        let first = OryFlow(id: "flow-1", kind: .login, expiresAt: nil, messages: [], nodes: [], actions: [],
                            submission: OrySubmission(action: action, method: "POST", values: ["csrf_token": "a"]))
        let second = OryFlow(id: "flow-1", kind: .login, expiresAt: nil, messages: [], nodes: [], actions: [],
                             submission: OrySubmission(action: action, method: "POST", values: ["csrf_token": "b"]))

        #expect(first != second)
    }

    @Test("Given flow results, when they are compared, then the case and its value decide")
    func flowResults() {
        let success = OryFlowResult<OryVerificationResult>.success(OryVerificationResult())
        let pending = OryFlowResult<OryVerificationResult>.pending(Sample.flow(kind: .verification))

        #expect(success == .success(OryVerificationResult()))
        #expect(pending == .pending(Sample.flow(kind: .verification)))
        #expect(success != pending)
        #expect(Set([success, pending, success]).count == 2)
    }

    @Test("Given results with equal and different values, when they are compared, then only equal values match")
    func results() {
        let session = Sample.session()
        let otherSession = Sample.session(id: "session-2")
        let verification = OryVerificationHandle(flowID: "v-1", address: "alex@example.com")

        #expect(OryAuthenticatedSession(session: session) == OryAuthenticatedSession(session: session))
        #expect(OryAuthenticatedSession(session: session) != OryAuthenticatedSession(session: otherSession))

        #expect(OryLoginResult(session: session, verification: verification) == OryLoginResult(session: session, verification: verification))
        #expect(OryLoginResult(session: session) != OryLoginResult(session: session, verification: verification))

        let identity = Sample.identity()
        #expect(OryRegistrationResult(identity: identity, session: nil) == OryRegistrationResult(identity: identity, session: nil))
        #expect(OryRegistrationResult(identity: identity, session: nil) != OryRegistrationResult(identity: identity, session: OryAuthenticatedSession(session: session)))

        #expect(OryRecoveryResult(settings: OrySettingsHandle(flowID: "s-1")) == OryRecoveryResult(settings: OrySettingsHandle(flowID: "s-1")))
        #expect(OryRecoveryResult(settings: OrySettingsHandle(flowID: "s-1")) != OryRecoveryResult(settings: nil))

        #expect(OrySettingsResult(identity: identity) == OrySettingsResult(identity: identity))
        #expect(OrySettingsResult(identity: identity) != OrySettingsResult(identity: identity, verification: verification))

        #expect(OryVerificationResult() == OryVerificationResult())
        #expect(Set([OryLoginResult(session: session), OryLoginResult(session: session)]).count == 1)
    }

    @Test("Given form values, when they are compared, then the entered values decide")
    func formValues() {
        var first = OryFormValues()
        first[.identifier] = "alex@example.com"
        var second = OryFormValues()
        second[.identifier] = "alex@example.com"
        var third = OryFormValues()
        third[.identifier] = "sam@example.com"

        #expect(first == second)
        #expect(first != third)
        #expect(Set([first, second, third]).count == 2)
    }

    @Test("Given errors without values, when they are compared, then the case decides")
    func errorsWithoutValues() {
        #expect(OryClientError.sessionExpired == .sessionExpired)
        #expect(OryClientError.sessionExpired != .notAuthenticated)
        #expect(OryClientError.deviceAuthenticationInvalidPIN == .deviceAuthenticationInvalidPIN)
        #expect(OryClientError.deviceAuthenticationInvalidPIN != .deviceAuthenticationPINRequired)
    }

    @Test("Given errors with values, when they are compared, then the values decide")
    func errorsWithValues() {
        #expect(OryClientError.flowExpired(replacementFlowID: "a") == .flowExpired(replacementFlowID: "a"))
        #expect(OryClientError.flowExpired(replacementFlowID: "a") != .flowExpired(replacementFlowID: nil))
        #expect(OryClientError.rateLimited(retryAfter: 30) != .rateLimited(retryAfter: 60))

        let message = OryUIMessage(id: 4000006, text: "Invalid credentials.", kind: .error)
        #expect(OryClientError.server(status: 400, id: nil, messages: [message]) == .server(status: 400, id: nil, messages: [message]))
        #expect(OryClientError.server(status: 400, id: nil, messages: [message]) != .server(status: 500, id: nil, messages: [message]))

        let handle = OryVerificationHandle(flowID: "v-1", address: "alex@example.com")
        #expect(OryClientError.addressVerificationRequired(handle) == .addressVerificationRequired(handle))
    }

    @Test("Given errors with underlying errors, when they are compared, then the bridged domain and code decide")
    func errorsWithUnderlyingErrors() {
        #expect(OryClientError.network(underlying: URLError(.timedOut)) == .network(underlying: URLError(.timedOut)))
        #expect(OryClientError.network(underlying: URLError(.timedOut)) != .network(underlying: URLError(.notConnectedToInternet)))
        #expect(OryClientError.network(underlying: URLError(.timedOut)) != .storage(underlying: URLError(.timedOut)))
        #expect(OryClientError.deviceAuthenticationFailed(underlying: CocoaError(.fileNoSuchFile))
            == .deviceAuthenticationFailed(underlying: CocoaError(.fileNoSuchFile)))
    }
}
