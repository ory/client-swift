import Foundation
import Testing
@testable import Ory

@Suite("FrontendGateway error classification")
struct FrontendGatewayTests {

    private func error(status: Int, body: Data = Data(), headers: [String: String] = [:]) -> OryClientError {
        FrontendGateway(client: MockHTTPClient(data: Data(), statusCode: status)).error(
            from: HTTPResponse<OryEmptyResponse>(status: status, data: body, headers: headers)
        )
    }

    private func genericBody(id: String, message: String = "…") -> Data {
        Data(#"{"error":{"id":"\#(id)","message":"\#(message)"}}"#.utf8)
    }

    @Test("session_aal2_required asks for a second factor")
    func aal2Required() {
        let mapped = error(status: 403, body: genericBody(id: "session_aal2_required"))

        #expect(mapped.isSecondFactorRequired)
    }

    @Test("An unverified address at sign-in carries the verification flow to open")
    func verifiedAddressRequired() {
        let mapped = error(status: 403, body: Fixture.errorVerifiedAddressRequired)

        guard case let .addressVerificationRequired(verification) = mapped else {
            Issue.record("expected addressVerificationRequired, got \(mapped)")
            return
        }
        #expect(verification == OryVerificationHandle(flowID: "verification-12", address: "alice@example.com"))
    }

    @Test("An unverified address without a verification flow keeps its id")
    func verifiedAddressRequiredWithoutFlow() {
        // Given the legacy error, which names no verification flow
        let mapped = error(status: 400, body: genericBody(id: "session_verified_address_required"))

        #expect(mapped.serverStatus == 400)
        #expect(mapped.serverID == .sessionVerifiedAddressRequired)
    }

    @Test("session_aal2_enrollment_required is not the same as needing a second factor")
    func aal2EnrollmentRequired() {
        // The identity has no second factor yet: the app must offer enrollment, not a prompt
        // for a factor the user does not have.
        let mapped = error(status: 403, body: genericBody(id: "session_aal2_enrollment_required"))

        guard case .secondFactorEnrollmentRequired = mapped else {
            Issue.record("expected secondFactorEnrollmentRequired, got \(mapped)")
            return
        }
    }

    @Test("session_refresh_required asks for re-authentication, not a new sign-in")
    func refreshRequired() {
        // The session is valid but too old for a privileged change. Reporting this as an
        // expired session sends the user through a full sign-in they do not need.
        let mapped = error(status: 403, body: genericBody(id: "session_refresh_required"))

        guard case .reauthenticationRequired = mapped else {
            Issue.record("expected reauthenticationRequired, got \(mapped)")
            return
        }
    }

    @Test("an inactive session is an expired session")
    func inactiveSession() {
        #expect(error(status: 401, body: genericBody(id: "session_inactive")).isSessionExpired)
    }

    @Test("a 401 without an id is an expired session")
    func unauthorizedWithoutID() {
        // Given the body whoami returns for a missing, invalid, expired or revoked token
        let body = Data(#"""
        {"error":{"code":401,"status":"Unauthorized","reason":"No valid session credentials found in the request.","message":"The request could not be authorized"}}
        """#.utf8)

        // Then
        #expect(error(status: 401, body: body).isSessionExpired)
        #expect(error(status: 401).isSessionExpired)
    }

    @Test("a 401 with an id other than session_inactive keeps the id")
    func unauthorizedWithOtherID() {
        // Given a 401 that does not mean the session is gone
        let mapped = error(status: 401, body: genericBody(id: "session_aal_already_fulfilled"))

        // Then
        #expect(mapped.serverStatus == 401)
        #expect(mapped.serverID == OryErrorID(rawValue: "session_aal_already_fulfilled"))
    }

    @Test("a 403 with an id this build does not recognize keeps the id")
    func forbiddenWithUnknownID() {
        let mapped = error(status: 403, body: genericBody(id: "some_future_condition"))

        #expect(mapped.serverStatus == 403)
        #expect(mapped.serverID == OryErrorID(rawValue: "some_future_condition"))
    }

    @Test("session_credential_required is a server error with its id")
    func credentialRequired() {
        let mapped = error(status: 403, body: genericBody(id: "session_credential_required"))

        #expect(mapped.serverStatus == 403)
        #expect(mapped.serverID == .sessionCredentialRequired)
    }

    @Test("a 403 without an Ory error body is a server error")
    func forbiddenWithoutOryBody() {
        // Given a 403 from a proxy in front of Ory: empty, plain text or an HTML page
        let bodies = [Data(), Data("invalid request path".utf8), Data("<html><body>Access denied</body></html>".utf8)]

        // Then
        for body in bodies {
            let mapped = error(status: 403, body: body)
            #expect(mapped.serverStatus == 403)
            #expect(mapped.serverID == nil)
        }
    }

    @Test("410 surfaces the replacement flow the server prepared")
    func flowExpired() {
        let mapped = error(status: 410, body: Fixture.errorFlowExpired)

        guard case let .flowExpired(replacementFlowID) = mapped else {
            Issue.record("expected flowExpired, got \(mapped)")
            return
        }
        #expect(replacementFlowID == "a7f0b3d4-1f6b-4e2c-9d5a-8c1e2b3f4a5d")
    }

    @Test("422 with redirect_browser_to carries the URL the browser must open")
    func browserLocationChange() {
        let body = Data(#"""
        {"error":{"id":"browser_location_change_required","code":422,"message":"..."},"redirect_browser_to":"https://accounts.example.com/authorize?state=abc"}
        """#.utf8)

        let mapped = error(status: 422, body: body)

        guard case let .browserLocationChangeRequired(redirectURL) = mapped else {
            Issue.record("expected browserLocationChangeRequired, got \(mapped)")
            return
        }
        #expect(redirectURL.absoluteString == "https://accounts.example.com/authorize?state=abc")
    }

    @Test("422 without redirect_browser_to stays a server error with its id")
    func unprocessableWithoutRedirect() {
        let mapped = error(status: 422, body: genericBody(id: "browser_location_change_required"))

        guard case let .server(status, id, _) = mapped else {
            Issue.record("expected server, got \(mapped)")
            return
        }
        #expect(status == 422)
        #expect(id == .browserLocationChangeRequired)
    }

    @Test("429 carries the server's Retry-After so the app can back off")
    func rateLimited() {
        let mapped = error(status: 429, headers: ["Retry-After": "30"])

        guard case let .rateLimited(retryAfter) = mapped else {
            Issue.record("expected rateLimited, got \(mapped)")
            return
        }
        #expect(retryAfter == 30)
    }

    @Test("429 without a Retry-After is still a rate limit")
    func rateLimitedWithoutHeader() {
        guard case let .rateLimited(retryAfter) = error(status: 429) else {
            Issue.record("expected rateLimited")
            return
        }
        #expect(retryAfter == nil)
    }

    @Test("any other status keeps the status, the error id, and the messages")
    func serverError() {
        let mapped = error(status: 500, body: genericBody(id: "identity_disabled", message: "Account disabled"))

        guard case let .server(status, id, messages) = mapped else {
            Issue.record("expected server, got \(mapped)")
            return
        }
        #expect(status == 500)
        #expect(id == .identityDisabled)
        #expect(messages.first?.text == "Account disabled")
    }
}
