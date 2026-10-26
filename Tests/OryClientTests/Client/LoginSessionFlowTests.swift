import Foundation
import Testing
import OryClientTestDoubles
@testable import OryClient

@Suite("Re-authentication and second-factor login flows")
struct LoginSessionFlowTests {

    // MARK: - Request

    @Test("A default login flow sends no query and no session token")
    func defaultRequest() async throws {
        // Given
        let (repository, network) = makeRepository(flow: Fixture.loginFlow)

        // When
        _ = try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/self-service/login/api")
        #expect(request?.sessionToken == nil)
    }

    @Test("refresh and aal are sent as query items together with the session token")
    func sessionRequest() async throws {
        // Given
        let (repository, network) = makeRepository(flow: Fixture.loginFlow)

        // When
        _ = try await repository.createLoginFlow(
            options: OryLoginFlowOptions(refresh: true, aal: .aal2),
            sessionToken: "ory_st_abc"
        )

        // Then
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/self-service/login/api?refresh=true&aal=aal2")
        #expect(request?.sessionToken == "ory_st_abc")
    }

    // MARK: - Mapping

    @Test(
        "A login flow is submitted with the session token only when it refreshes or requests AAL2",
        arguments: [
            (refresh: false, aal: "aal1", expected: false),
            (refresh: true, aal: "aal1", expected: true),
            (refresh: false, aal: "aal2", expected: true),
        ]
    )
    func sendsSessionToken(refresh: Bool, aal: String, expected: Bool) async throws {
        // Given a login flow with the server's refresh and requested_aal values
        let data = try loginFlow(refresh: refresh, requestedAAL: aal)
        let (repository, _) = makeRepository(flow: data)

        // When
        let flow = try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then
        #expect(flow.submission.sendsSessionToken == expected)
    }

    // MARK: - Client

    @Test("A refresh or AAL2 flow without a stored session throws notAuthenticated and skips the network")
    func sessionFlowWithoutToken() async throws {
        // Given a client without a stored session
        let frontend = FakeFrontendRepository(createLoginFlow: .success(Sample.loginFlow()))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        // When / Then
        for options in [OryLoginFlowOptions(refresh: true), OryLoginFlowOptions(aal: .aal2)] {
            let error = await #expect(throws: OryClientError.self) {
                _ = try await client.createLoginFlow(options: options)
            }
            #expect(error?.isNotAuthenticated == true)
        }
        #expect(await frontend.receivedLoginFlowOptions == nil)
    }

    @Test("A refresh flow is created with the stored session token")
    func sessionFlowWithToken() async throws {
        // Given a stored session
        let frontend = FakeFrontendRepository(createLoginFlow: .success(Sample.loginFlow()))
        let client = OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st_abc"),
            frontend: frontend,
            deviceAuthn: frontend
        )

        // When
        _ = try await client.createLoginFlow(options: OryLoginFlowOptions(refresh: true))

        // Then
        #expect(await frontend.receivedLoginFlowOptions == OryLoginFlowOptions(refresh: true))
        #expect(await frontend.receivedLoginSessionToken == "ory_st_abc")
    }

    @Test("A first-factor login flow is created without the session token, even when one is stored")
    func firstFactorFlowWithStoredToken() async throws {
        // Given a stored session
        let frontend = FakeFrontendRepository(createLoginFlow: .success(Sample.loginFlow()))
        let client = OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st_abc"),
            frontend: frontend,
            deviceAuthn: frontend
        )

        // When
        _ = try await client.createLoginFlow()

        // Then
        #expect(await frontend.receivedLoginFlowOptions == OryLoginFlowOptions())
        #expect(await frontend.receivedLoginSessionToken == nil)
    }

    @Test("Submitting a flow that belongs to the session sends the stored token and stores the returned one")
    func submitSessionFlow() async throws {
        // Given a stored session and an AAL2 flow
        let storage = InMemorySessionStorage(initialToken: "ory_st_abc")
        let frontend = FakeFrontendRepository(
            submitLogin: .success(.success(session: Sample.session(), token: "ory_st_abc"))
        )
        let client = OryClient(storage: storage, frontend: frontend, deviceAuthn: frontend)

        // When
        let result = try await client.submitLoginFlow(
            sessionFlow(),
            values: OryFormValues(),
            pressing: Sample.submitAction(value: "totp")
        )

        // Then
        guard case .success = result else {
            Issue.record("expected success")
            return
        }
        #expect(await frontend.receivedLoginSessionToken == "ory_st_abc")
        #expect(try await storage.sessionToken() == "ory_st_abc")
    }

    @Test("Submitting a first-factor flow does not send the stored token")
    func submitFirstFactorFlow() async throws {
        // Given a stored session and a regular login flow
        let frontend = FakeFrontendRepository(submitLogin: .success(.pending(Sample.loginFlow())))
        let client = OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st_abc"),
            frontend: frontend,
            deviceAuthn: frontend
        )

        // When
        _ = try await client.submitLoginFlow(Sample.loginFlow(), values: OryFormValues(), pressing: Sample.submitAction())

        // Then
        #expect(await frontend.receivedLoginSessionToken == nil)
    }

    @Test("Submitting a flow that belongs to the session without a stored token throws notAuthenticated")
    func submitSessionFlowWithoutToken() async throws {
        // Given no stored session
        let frontend = FakeFrontendRepository(submitLogin: .success(.pending(Sample.loginFlow())))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        // When / Then
        let error = await #expect(throws: OryClientError.self) {
            _ = try await client.submitLoginFlow(sessionFlow(), values: OryFormValues(), pressing: Sample.submitAction())
        }
        #expect(error?.isNotAuthenticated == true)
        #expect(await frontend.submitCallCount == 0)
    }

    // MARK: - Helpers

    private func makeRepository(flow: Data) -> (LiveFrontendRepository, MockHTTPClient) {
        let network = MockHTTPClient(data: flow, statusCode: 200)
        return (LiveFrontendRepository(gateway: FrontendGateway(client: network)), network)
    }

    private func loginFlow(refresh: Bool, requestedAAL: String) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: Fixture.loginFlow) as? [String: Any])
        json["refresh"] = refresh
        json["requested_aal"] = requestedAAL
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func sessionFlow() -> OryFlow {
        OryFlow(
            id: "flow-aal2",
            kind: .login,
            expiresAt: .distantFuture,
            messages: [],
            nodes: [],
            actions: [],
            submission: OrySubmission(
                action: URL(string: "https://example.com/self-service/login?flow=flow-aal2")!,
                method: "POST",
                values: [:],
                sendsSessionToken: true
            )
        )
    }
}
