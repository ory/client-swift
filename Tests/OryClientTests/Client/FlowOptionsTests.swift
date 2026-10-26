import Foundation
import Testing
@testable import OryClient

@Suite("Create flow options")
struct FlowOptionsTests {

    @Test("A hand-written conformance gets create methods without options that pass the defaults")
    func defaultOptionsForwarding() async throws {
        // Given a test double that implements only the requirements that take options
        let flows = RecordingFlows()

        // When the parameterless convenience methods are called
        _ = try await flows.createLoginFlow()
        _ = try await flows.createRegistrationFlow()
        _ = try await flows.createVerificationFlow()
        _ = try await flows.createRecoveryFlow()
        _ = try await flows.createSettingsFlow()

        // Then each forwarded default options
        #expect(await flows.login == [OryLoginFlowOptions()])
        #expect(await flows.registration == [OryRegistrationFlowOptions()])
        #expect(await flows.verification == [OryVerificationFlowOptions()])
        #expect(await flows.recovery == [OryRecoveryFlowOptions()])
        #expect(await flows.settings == [OrySettingsFlowOptions()])
    }
}

private actor RecordingFlows:
    OryLoginFlow, OryRegistrationFlow, OryVerificationFlow, OryRecoveryFlow, OrySettingsFlow
{
    var login: [OryLoginFlowOptions] = []
    var registration: [OryRegistrationFlowOptions] = []
    var verification: [OryVerificationFlowOptions] = []
    var recovery: [OryRecoveryFlowOptions] = []
    var settings: [OrySettingsFlowOptions] = []

    func createLoginFlow(options: OryLoginFlowOptions) async throws -> OryFlow {
        login.append(options)
        return Sample.flow(kind: .login)
    }

    func createRegistrationFlow(options: OryRegistrationFlowOptions) async throws -> OryFlow {
        registration.append(options)
        return Sample.flow(kind: .registration)
    }

    func createVerificationFlow(options: OryVerificationFlowOptions) async throws -> OryFlow {
        verification.append(options)
        return Sample.flow(kind: .verification)
    }

    func createRecoveryFlow(options: OryRecoveryFlowOptions) async throws -> OryFlow {
        recovery.append(options)
        return Sample.flow(kind: .recovery)
    }

    func createSettingsFlow(options: OrySettingsFlowOptions) async throws -> OryFlow {
        settings.append(options)
        return Sample.flow(kind: .settings)
    }

    func getLoginFlow(id: String) async throws -> OryFlow { Sample.flow(kind: .login) }

    func getRegistrationFlow(id: String) async throws -> OryFlow { Sample.flow(kind: .registration) }

    func getRecoveryFlow(id: String) async throws -> OryFlow { Sample.flow(kind: .recovery) }

    func getVerificationFlow(id: String) async throws -> OryFlow { Sample.flow(kind: .verification) }

    func getSettingsFlow(id: String) async throws -> OryFlow { Sample.flow(kind: .settings) }

    func submitLoginFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryAuthenticatedSession> { .pending(flow) }

    func submitRegistrationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRegistrationResult> { .pending(flow) }

    func submitVerificationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryVerificationResult> { .pending(flow) }

    func submitRecoveryFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRecoveryResult> { .pending(flow) }

    func submitSettingsFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OrySettingsResult> { .pending(flow) }
}
