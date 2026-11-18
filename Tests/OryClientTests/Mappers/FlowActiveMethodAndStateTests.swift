import Foundation
import Testing
@testable import Ory

@Suite("OryFlow active method, state and submitted identifier")
struct FlowActiveMethodAndStateTests {

    private static let allKinds: [OryFlowKind] = [.login, .registration, .recovery, .verification, .settings]

    private func fixture(for kind: OryFlowKind) -> Data {
        switch kind {
        case .login: Fixture.loginFlow
        case .registration: Fixture.registrationFlow
        case .recovery: Fixture.recoveryFlow
        case .verification: Fixture.verificationFlow
        case .settings: Fixture.settingsFlow
        }
    }

    /// Returns the fixture of `kind` with `active` and `state` replaced; `nil` removes the field.
    private func flowData(_ kind: OryFlowKind, active: String?, state: String) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: fixture(for: kind)) as? [String: Any])
        json["active"] = active
        json["state"] = state
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func flow(_ kind: OryFlowKind, from data: Data) async throws -> OryFlow {
        let network = MockHTTPClient(data: data, statusCode: 200)
        let repository = LiveFrontendRepository(gateway: FrontendGateway(client: network))
        return switch kind {
        case .login: try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)
        case .registration: try await repository.createRegistrationFlow()
        case .recovery: try await repository.createRecoveryFlow()
        case .verification: try await repository.createVerificationFlow()
        case .settings: try await repository.createSettingsFlow(sessionToken: "token")
        }
    }

    @Test("Given a flow with an active method and a state, when it is mapped, then both are kept", arguments: allKinds)
    func mapsActiveAndState(kind: OryFlowKind) async throws {
        let state: OryFlowState = kind == .settings ? .success : .sentEmail
        let data = try flowData(kind, active: "code", state: state.rawValue)

        let flow = try await flow(kind, from: data)

        #expect(flow.activeMethod == .code)
        #expect(flow.state == state)
    }

    @Test("Given a flow without an active method, when it is mapped, then the active method is nil", arguments: allKinds)
    func missingActive(kind: OryFlowKind) async throws {
        let data = try flowData(kind, active: nil, state: kind == .settings ? "show_form" : "choose_method")

        let flow = try await flow(kind, from: data)

        #expect(flow.activeMethod == nil)
        #expect(flow.state == (kind == .settings ? .showForm : .chooseMethod))
    }

    @Test("Given a state newer than this version, when the flow is mapped, then the state is nil and the flow still maps", arguments: allKinds)
    func unknownState(kind: OryFlowKind) async throws {
        let data = try flowData(kind, active: "password", state: "brand_new_state")

        let flow = try await flow(kind, from: data)

        #expect(flow.state == nil)
        #expect(flow.activeMethod == .password)
    }

    @Test("Given a login or registration with a method newer than this version, when it is mapped, then the active method is nil", arguments: [OryFlowKind.login, .registration])
    func unknownEnumMethod(kind: OryFlowKind) async throws {
        let data = try flowData(kind, active: "brand_new_method", state: "choose_method")

        let flow = try await flow(kind, from: data)

        #expect(flow.activeMethod == nil)
    }

    @Test("Given a recovery, verification or settings flow with a method this version does not list, when it is mapped, then the method is kept", arguments: [OryFlowKind.recovery, .verification, .settings])
    func unknownStringMethod(kind: OryFlowKind) async throws {
        let data = try flowData(kind, active: "brand_new_method", state: "choose_method")

        let flow = try await flow(kind, from: data)

        #expect(flow.activeMethod == OryNodeGroup(rawValue: "brand_new_method"))
    }

    @Test("Given a login past the identifier-first step, when it is mapped, then it reports the step and the identifier")
    func identifierFirstSecondStep() async throws {
        let flow = try await flow(.login, from: Fixture.loginFlowIdentifierFirstCredentials)

        #expect(flow.activeMethod == .identifierFirst)
        #expect(flow.submittedIdentifier == "alex@example.com")
        #expect(flow.availableMethods == [.password])
        #expect(flow.nodes.allSatisfy { $0.id != "identifier" })
    }

    @Test("Given a login past the identifier-first step, when it is submitted, then the hidden identifier is sent")
    func identifierFirstSubmitsIdentifier() async throws {
        let flow = try await flow(.login, from: Fixture.loginFlowIdentifierFirstCredentials)
        let action = try #require(flow.actions(in: .password).first)

        let body = flow.makeBody(values: flow.makeValues(), pressing: action)

        #expect(body.fields["identifier"] == "alex@example.com")
    }

    @Test("Given a login whose identifier field is visible, when it is mapped, then no identifier is submitted yet")
    func visibleIdentifierIsNotSubmitted() async throws {
        let flow = try await flow(.login, from: Fixture.loginFlow)

        #expect(flow.submittedIdentifier == nil)
    }

    @Test("Given a flow built for previews, when it sets the new fields, then it keeps them")
    func publicInitializer() {
        let flow = OryFlow(
            id: "preview",
            kind: .login,
            activeMethod: .identifierFirst,
            state: .chooseMethod,
            submittedIdentifier: "alex@example.com"
        )

        #expect(flow.activeMethod == .identifierFirst)
        #expect(flow.state == .chooseMethod)
        #expect(flow.submittedIdentifier == "alex@example.com")
    }
}
