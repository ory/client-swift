import Foundation
import Testing
@testable import Ory

@Suite("Message ids and context on labels, text nodes and links")
struct UITextMappingTests {

    private func repository(_ data: Data) -> LiveFrontendRepository {
        LiveFrontendRepository(gateway: FrontendGateway(client: MockHTTPClient(data: data, statusCode: 200)))
    }

    private func field(_ name: OryFieldName, in flow: OryFlow) -> OryInputField? {
        flow.nodes.lazy.compactMap { node -> OryInputField? in
            guard case let .input(field) = node.content, field.name == name else { return nil }
            return field
        }.first
    }

    @Test("Given an input with a label, when the flow is mapped, then the label keeps its id, text and kind")
    func inputLabel() async throws {
        let flow = try await repository(Fixture.loginFlow).createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        let label = try #require(field(.identifier, in: flow)?.label)

        #expect(label == OryUIMessage(id: 1010001, text: "Email", kind: .info))
    }

    @Test("Given a submit button with a label, when the flow is mapped, then the action's label keeps its id")
    func actionLabel() async throws {
        let flow = try await repository(Fixture.loginFlow).createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        #expect(flow.actions.first?.label?.id == 1010002)
        #expect(flow.actions.first?.label?.text == "Sign in")
    }

    @Test("Given an input without a label, when the flow is mapped, then the label is nil")
    func missingLabel() async throws {
        let flow = try await repository(Fixture.loginFlow).createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        #expect(field(.password, in: flow)?.label == nil)
    }

    @Test("Given a text node with context, when the flow is mapped, then the text keeps its id and context")
    func textNodeWithContext() async throws {
        let flow = try await repository(Fixture.settingsFlowTOTP).createSettingsFlow(sessionToken: "token")

        let node = try #require(flow.nodes.first { $0.id == "totp_secret_key" })
        guard case let .text(message) = node.content else {
            Issue.record("Expected a text node, got \(node.content)")
            return
        }

        #expect(message.id == 1050006)
        #expect(message.text == "JBSWY3DPEHPK3PXP")
        #expect(message.kind == .info)
        #expect(message.context == ["secret": .string("JBSWY3DPEHPK3PXP")])
        #expect(flow.totpSetup?.secret == "JBSWY3DPEHPK3PXP")
    }

    @Test("Given a label from the node's meta, when the flow is mapped, then the input's label is that message")
    func metaLabel() async throws {
        let flow = try await repository(Fixture.settingsFlowTOTP).createSettingsFlow(sessionToken: "token")

        #expect(field(.totpCode, in: flow)?.label == OryUIMessage(id: 1070006, text: "Verify code", kind: .info))
    }

    @Test("Given a link without context, when the flow is mapped, then its label keeps its id and has no context")
    func linkLabel() async throws {
        let flow = try await repository(Fixture.verificationFlowContinue).createVerificationFlow()

        let node = try #require(flow.nodes.first { $0.id == "continue" })
        guard case let .link(label, url) = node.content else {
            Issue.record("Expected a link node, got \(node.content)")
            return
        }

        #expect(label == OryUIMessage(id: 1070009, text: "Continue", kind: .info))
        #expect(label.context.isEmpty)
        #expect(url == URL(string: "https://example.com/welcome"))
    }

    @Test("Given a button label with context, when the flow is mapped, then the label keeps the context")
    func labelWithContext() async throws {
        var json = try #require(try JSONSerialization.jsonObject(with: Fixture.loginFlow) as? [String: Any])
        var ui = try #require(json["ui"] as? [String: Any])
        var nodes = try #require(ui["nodes"] as? [[String: Any]])
        nodes.append([
            "type": "input",
            "group": "oidc",
            "messages": [],
            "meta": ["label": [
                "id": 1010002,
                "text": "Sign in with Google",
                "type": "info",
                "context": ["provider": "Google", "provider_id": "google"],
            ]],
            "attributes": ["node_type": "input", "name": "provider", "type": "submit", "value": "google", "disabled": false],
        ])
        ui["nodes"] = nodes
        json["ui"] = ui
        let data = try JSONSerialization.data(withJSONObject: json)

        let flow = try await repository(data).createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        let label = try #require(flow.actions(in: .oidc).first?.label)
        #expect(label.id == 1010002)
        #expect(label.text == "Sign in with Google")
        #expect(label.context == ["provider": .string("Google"), "provider_id": .string("google")])
    }
}
