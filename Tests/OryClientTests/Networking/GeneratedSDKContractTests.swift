import Foundation
import OrySDK
import Testing
@testable import OryClient

@Suite("Generated SDK contract")
struct GeneratedSDKContractTests {

    @Test("session responses preserve the code authentication channel", arguments: ["email", "sms"])
    func preservesAuthenticationChannel(channel: String) throws {
        let body = Data("""
        {
            "id": "8c420f3d-9131-4b1d-9c7c-99a7f7ba275d",
            "authentication_methods": [{"method": "code", "aal": "aal1", "channel": "\(channel)"}]
        }
        """.utf8)
        let response = HTTPResponse<OrySDKAPI.Session>(status: 200, data: body)

        let session = try response.success()
        let encoded = try JSONEncoder().encode(session)

        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let methods = try #require(json["authentication_methods"] as? [[String: Any]])
        let method = try #require(methods.first)
        #expect(method["channel"] as? String == channel)
        #expect(method["method"] as? String == "code")
    }

    @Test("unknown recovery states keep the flow pending")
    func unknownRecoveryState() async throws {
        let repository = try repositoryWithUnknownState(Fixture.recoveryFlow)

        let outcome = try await repository.submitRecovery(url: URL(string: "https://example.com/recovery")!, fields: [:])

        guard case let .pending(flow) = outcome else {
            Issue.record("Expected an unknown recovery state to remain pending")
            return
        }
        #expect(!flow.nodes.isEmpty)
    }

    @Test("unknown verification states keep the flow pending")
    func unknownVerificationState() async throws {
        let repository = try repositoryWithUnknownState(Fixture.verificationFlow)

        let outcome = try await repository.submitVerification(url: URL(string: "https://example.com/verification")!, fields: [:])

        guard case let .pending(flow) = outcome else {
            Issue.record("Expected an unknown verification state to remain pending")
            return
        }
        #expect(!flow.nodes.isEmpty)
    }

    @Test("unknown settings states keep the flow pending")
    func unknownSettingsState() async throws {
        let repository = try repositoryWithUnknownState(Fixture.settingsFlow)

        let outcome = try await repository.submitSettings(url: URL(string: "https://example.com/settings")!, fields: [:], sessionToken: "token")

        guard case let .pending(flow) = outcome else {
            Issue.record("Expected an unknown settings state to remain pending")
            return
        }
        #expect(!flow.nodes.isEmpty)
    }

    private func repositoryWithUnknownState(_ fixture: Data) throws -> LiveFrontendRepository {
        var json = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        json["state"] = "future_server_state"
        let data = try JSONSerialization.data(withJSONObject: json)
        return LiveFrontendRepository(gateway: FrontendGateway(client: MockHTTPClient(data: data, statusCode: 200)))
    }
}
