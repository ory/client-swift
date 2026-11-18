import Foundation
import OryTestDoubles
import Testing
@testable import Ory

@Suite("Elements configuration")
struct ElementsConfigurationTests {

    private func makeRepository(data: Data, status: Int) -> (LiveFrontendRepository, MockHTTPClient) {
        let network = MockHTTPClient(data: data, statusCode: status)
        return (LiveFrontendRepository(gateway: FrontendGateway(client: network)), network)
    }

    @Test("Given a full configuration, when it is loaded, then every field is mapped")
    func mapsFullConfiguration() async throws {
        let (repository, network) = makeRepository(data: Fixture.elementsConfiguration, status: 200)

        let configuration = try await repository.elementsConfiguration()

        #expect(configuration == OryElementsConfiguration(
            name: "Acme",
            logoLightURL: URL(string: "https://cdn.example.com/acme-light.png"),
            logoDarkURL: URL(string: "https://cdn.example.com/acme-dark.png"),
            registrationEnabled: false,
            hideRegistrationLink: true,
            verificationEnabled: true,
            recoveryEnabled: false,
            termsOfServiceURL: URL(string: "https://example.com/terms"),
            privacyPolicyURL: URL(string: "https://example.com/privacy"),
            contactURL: URL(string: "mailto:help@example.com"),
            hideOryBranding: true
        ))
        let request = await network.lastRequest
        #expect(request?.url.absoluteString == "https://example.com/elements/configuration")
        #expect(request?.sessionToken == nil)
    }

    @Test("Given unset URLs as empty strings, when the configuration is loaded, then they are nil")
    func mapsEmptyURLsToNil() async throws {
        let (repository, _) = makeRepository(data: Fixture.elementsConfigurationMinimal, status: 200)

        let configuration = try await repository.elementsConfiguration()

        #expect(configuration == OryElementsConfiguration(name: "Acme"))
    }

    @Test("Given an unknown project host, when the configuration is loaded, then the 404 is a server error")
    func unknownHost() async throws {
        let body = Data(#"{"error":{"code":404,"status":"Not Found","message":"Unable to locate the resource"}}"#.utf8)
        let (repository, _) = makeRepository(data: body, status: 404)

        do {
            _ = try await repository.elementsConfiguration()
            Issue.record("expected to throw")
        } catch OryClientError.server(let status, _, _) {
            #expect(status == 404)
        }
    }

    @Test("Given a network failure, when the client loads the configuration, then the error is passed on")
    func clientPassesNetworkError() async throws {
        let frontend = FakeFrontendRepository(elementsConfiguration: .failure(.network(underlying: URLError(.notConnectedToInternet))))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        do {
            _ = try await client.elementsConfiguration()
            Issue.record("expected to throw")
        } catch OryClientError.network {
        }
        #expect(await frontend.elementsConfigurationCallCount == 1)
    }

    @Test("Given a signed-out client, when it loads the configuration, then it returns the repository's configuration")
    func clientReturnsConfiguration() async throws {
        let expected = OryElementsConfiguration(name: "Acme", hideOryBranding: true)
        let frontend = FakeFrontendRepository(elementsConfiguration: .success(expected))
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        #expect(try await client.elementsConfiguration() == expected)
    }

    @Test("Given a stub with a configuration, when it is loaded, then the stub returns it and counts the call")
    func stubReturnsConfiguration() async throws {
        let expected = OryElementsConfiguration(name: "Acme", recoveryEnabled: false)
        let stub = OryClientStub(elementsConfigurationResult: .success(expected))

        #expect(try await stub.elementsConfiguration() == expected)
        #expect(await stub.elementsConfigurationCallCount == 1)
    }
}
