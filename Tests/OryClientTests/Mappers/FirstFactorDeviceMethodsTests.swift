import Foundation
import Testing
@testable import Ory

@Suite("OryFlow first-factor device methods")
struct FirstFactorDeviceMethodsTests {

    private func loginFlow(from data: Data) async throws -> OryFlow {
        let network = MockHTTPClient(data: data, statusCode: 200)
        let repository = LiveFrontendRepository(gateway: FrontendGateway(client: network))
        return try await repository.createLoginFlow(options: OryLoginFlowOptions(), sessionToken: nil)
    }

    @Test("Given an options node that lists PIN and platform keys for iOS, when the flow is mapped, then PIN and biometric sign-in are first factors")
    func mapsIOSList() async throws {
        let flow = try await loginFlow(from: Fixture.loginFlowDeviceAuthnFirstFactor)

        #expect(flow.firstFactorDeviceMethods == [.pin, .biometric])
    }

    @Test("Given a device flow without the options node, when the flow is mapped, then no device method is a first factor")
    func missingListMeansNone() async throws {
        let flow = try await loginFlow(from: Fixture.loginFlowDeviceAuthn)

        #expect(flow.firstFactorDeviceMethods.isEmpty)
    }

    @Test("Given a flow without device authentication, when it is mapped, then no device method is a first factor")
    func noDeviceAuthn() async throws {
        let flow = try await loginFlow(from: Fixture.loginFlow)

        #expect(flow.firstFactorDeviceMethods.isEmpty)
    }

    @Test("Given a flow built for previews, when it lists methods, then it keeps them")
    func publicInitializer() {
        let flow = OryFlow(id: "preview", kind: .login, firstFactorDeviceMethods: [.pin])

        #expect(flow.firstFactorDeviceMethods == [.pin])
    }
}
