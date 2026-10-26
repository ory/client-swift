import Foundation
import Testing
@testable import OryClient

@Suite("Get flow by id")
struct GetFlowByIDTests {

    private func makeRepository(data: Data, status: Int = 200) -> (LiveFrontendRepository, MockHTTPClient) {
        let network = MockHTTPClient(data: data, statusCode: status)
        return (LiveFrontendRepository(gateway: FrontendGateway(client: network)), network)
    }

    @Test("getLoginFlow fetches the flow by id without a session token")
    func login() async throws {
        let (repository, network) = makeRepository(data: Fixture.loginFlow)

        let flow = try await repository.getLoginFlow(id: "login-1")

        #expect(flow.kind == .login)
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/self-service/login/flows?id=login-1")
        #expect(request?.sessionToken == nil)
    }

    @Test("getRegistrationFlow fetches the flow by id")
    func registration() async throws {
        let (repository, network) = makeRepository(data: Fixture.registrationFlow)

        let flow = try await repository.getRegistrationFlow(id: "registration-1")

        #expect(flow.kind == .registration)
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/self-service/registration/flows?id=registration-1")
    }

    @Test("getRecoveryFlow fetches the flow by id")
    func recovery() async throws {
        let (repository, network) = makeRepository(data: Fixture.recoveryFlow)

        let flow = try await repository.getRecoveryFlow(id: "recovery-1")

        #expect(flow.kind == .recovery)
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/self-service/recovery/flows?id=recovery-1")
    }

    @Test("An expired flow fetched by id throws flowExpired")
    func expired() async throws {
        let (repository, _) = makeRepository(data: Fixture.errorFlowExpired, status: 410)

        let error = await #expect(throws: OryClientError.self) {
            _ = try await repository.getLoginFlow(id: "login-1")
        }

        guard case .flowExpired = error else {
            Issue.record("Expected flowExpired, got \(String(describing: error))")
            return
        }
    }
}
