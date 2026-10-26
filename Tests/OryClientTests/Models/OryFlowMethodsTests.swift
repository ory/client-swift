import Foundation
import Testing
@testable import OryClient

@Suite("OryFlow methods")
struct OryFlowMethodsTests {

    private func action(_ value: String, group: OryNodeGroup) -> OryInputField {
        OryInputField(name: .method, kind: .submit, value: value, group: group)
    }

    private func node(_ name: String, group: OryNodeGroup) -> OryNode {
        OryNode(id: name, group: group, content: .input(OryInputField(name: OryFieldName(rawValue: name), kind: .text, group: group)))
    }

    @Test("availableMethods lists the groups of the actions once, in server order, without shared groups")
    func availableMethods() {
        // Given a login with identifier-first, password, code and a social provider
        let flow = OryFlow(id: "f", kind: .login, actions: [
            action("identifier_first", group: .identifierFirst),
            action("password", group: .password),
            action("code", group: .code),
            action("code", group: .code),
            action("google", group: .oidc),
            action("profile", group: .profile),
            action("continue", group: .default),
        ])

        // Then
        #expect(flow.availableMethods == [.password, .code, .oidc])
    }

    @Test("A settings flow lists the profile section as a method")
    func settingsProfile() {
        let flow = OryFlow(id: "f", kind: .settings, actions: [
            action("profile", group: .profile),
            action("password", group: .password),
        ])

        #expect(flow.availableMethods == [.profile, .password])
    }

    @Test("nodes(in:) and actions(in:) return one method's nodes and actions")
    func filterByGroup() {
        // Given
        let flow = OryFlow(
            id: "f",
            kind: .login,
            nodes: [node("identifier", group: .default), node("password", group: .password), node("code", group: .code)],
            actions: [action("password", group: .password), action("code", group: .code)]
        )

        // Then
        #expect(flow.nodes(in: .password).map(\.id) == ["password"])
        #expect(flow.nodes(in: .default).map(\.id) == ["identifier"])
        #expect(flow.actions(in: .code).map(\.value) == ["code"])
        #expect(flow.actions(in: .totp).isEmpty)
    }

    @Test("Mapped actions carry their node group")
    func mappedActionGroup() async throws {
        // Given a password login flow from the server
        let network = MockHTTPClient(data: Fixture.loginFlow, statusCode: 200)
        let repository = LiveFrontendRepository(gateway: FrontendGateway(client: network))

        // When
        let flow = try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then
        let password = try #require(flow.actions.first { $0.value == "password" })
        #expect(password.group == .password)
        #expect(flow.availableMethods == [.password])
        #expect(flow.requestedAAL == nil)
        #expect(!flow.isRefresh)
    }

    @Test("A login flow exposes the server's refresh and requested_aal")
    func mappedSessionFlow() async throws {
        // Given an AAL2 re-authentication flow
        var json = try #require(JSONSerialization.jsonObject(with: Fixture.loginFlow) as? [String: Any])
        json["refresh"] = true
        json["requested_aal"] = "aal2"
        let network = MockHTTPClient(data: try JSONSerialization.data(withJSONObject: json), statusCode: 200)
        let repository = LiveFrontendRepository(gateway: FrontendGateway(client: network))

        // When
        let flow = try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)

        // Then
        #expect(flow.isRefresh)
        #expect(flow.requestedAAL == .aal2)
    }

    @Test("resendCodeAction finds the code resend button of each flow kind")
    func resendCodeAction() {
        let login = OryFlow(id: "f", kind: .login, actions: [
            action("code", group: .code),
            OryInputField(name: .resend, kind: .submit, value: "code", group: .code),
        ])
        let recovery = OryFlow(id: "f", kind: .recovery, actions: [
            action("code", group: .code),
            OryInputField(name: .email, kind: .submit, value: "user@example.com", group: .code),
        ])
        let beforeSending = OryFlow(id: "f", kind: .login, actions: [action("code", group: .code)])

        #expect(login.resendCodeAction?.name == .resend)
        #expect(recovery.resendCodeAction?.name == .email)
        #expect(beforeSending.resendCodeAction == nil)
    }

    @Test("totpSetup decodes the QR data URL and reads the secret")
    func totpSetup() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let qr = try #require(URL(string: "data:image/png;base64,\(png.base64EncodedString())"))
        let flow = OryFlow(id: "f", kind: .settings, nodes: [
            OryNode(id: "totp_qr", group: .totp, content: .image(url: qr)),
            OryNode(id: "totp_secret_key", group: .totp, content: .text("SECRET")),
        ])

        #expect(flow.totpSetup == OryTOTPSetup(qrCodePNG: png, secret: "SECRET"))
        #expect(flow.totpUnlinkAction == nil)
    }

    @Test("A linked authenticator offers the unlink action instead of a setup")
    func totpLinked() {
        let flow = OryFlow(id: "f", kind: .settings, actions: [
            OryInputField(name: .totpUnlink, kind: .submit, value: "true", group: .totp),
        ])

        #expect(flow.totpSetup == nil)
        #expect(flow.totpUnlinkAction?.name == .totpUnlink)
    }

    @Test("previousStepAction is the back button of a two-step registration")
    func previousStep() {
        let credentials = OryFlow(id: "f", kind: .registration, actions: [
            action("password", group: .password),
            OryInputField(name: .screen, kind: .submit, value: "previous", group: .profile),
        ])
        let profile = OryFlow(id: "f", kind: .registration, actions: [action("profile", group: .profile)])

        #expect(credentials.previousStepAction?.name == .screen)
        #expect(credentials.availableMethods == [.password])
        #expect(profile.previousStepAction == nil)
        #expect(profile.availableMethods.isEmpty)
    }
}
