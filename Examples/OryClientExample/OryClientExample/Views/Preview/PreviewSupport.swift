#if DEBUG
import Foundation
import OryClient

/// Sample domain values for SwiftUI previews.
nonisolated enum PreviewData {

    static func session(aal: OryAuthenticatorAssuranceLevel = .aal2) -> OrySession {
        OrySession(
            id: "preview-session",
            isActive: true,
            expiresAt: nil,
            authenticatedAt: nil,
            authenticatorAssuranceLevel: aal,
            identity: OryIdentity(id: "preview-identity", schemaID: "default")
        )
    }

    /// This device, enrolled with a PIN and locked after too many wrong attempts — the state
    /// that routes the root into PIN recovery.
    static func lockedCurrentDevice() -> OryEnrolledDevice {
        OryEnrolledDevice(
            clientKeyID: "preview-key",
            name: "This iPhone",
            enrolledAt: Date(timeIntervalSince1970: 1_700_000_000),
            platform: .iOS,
            userVerification: .pin,
            isLocked: true,
            isCurrentDevice: true
        )
    }

    static func loginFlow() -> OryFlow {
        OryFlow(
            id: "preview-flow",
            kind: .login,
            nodes: [
                OryNode(
                    id: "identifier",
                    group: .default,
                    content: .input(OryInputField(name: .identifier, kind: .email, label: "Email", autocomplete: .email))
                ),
                OryNode(
                    id: "password",
                    group: .password,
                    content: .input(OryInputField(name: .password, kind: .password, label: "Password", autocomplete: .currentPassword))
                ),
            ],
            actions: [OryInputField(name: .method, kind: .submit, label: "Sign in", value: "password")]
        )
    }
}

/// A no-op ``OryClientProtocol`` for previews: it performs no real work, returning only the
/// benign values a preview needs to render a specific state. Configure the stored properties
/// to drive views whose `.task` reads them on appear.
struct PreviewOryClient: OryClientProtocol {

    var isDeviceAuthenticationAvailable = true
    var availableDeviceAuthenticationMethods: Set<OryDeviceAuthenticationMethod> = [.pin, .biometric]
    var biometryType: OryBiometryType = .faceID

    var currentSessionResult: Result<OrySession, OryClientError> = .failure(.notAuthenticated)
    var flow = PreviewData.loginFlow()
    /// When set, the flow-creating calls throw it — drives the `.failed` preview of a
    /// `.task`-loaded view.
    var createFlowError: OryClientError?
    var deviceEnrollmentState: OryDeviceEnrollmentState = .notEnrolled
    var enrolledDevicesList: [OryEnrolledDevice] = []
    /// When set, ``resetDevicePIN(newPin:)`` throws it; when `nil`, the reset succeeds. Defaults
    /// to a benign "cancelled" so previews that do not exercise recovery stay in a neutral state.
    var resetDevicePINError: OryClientError? = .deviceAuthenticationCancelled

    func currentSession() async throws -> OrySession { try currentSessionResult.get() }
    func logout() async throws {}

    func createLoginFlow() async throws -> OryFlow { try makeFlow() }
    func submitLoginFlow(_ flow: OryFlow, values: OryFormValues, pressing action: OryInputField) async throws -> OryFlowResult<OryAuthenticatedSession> {
        .pending(self.flow)
    }

    func createRegistrationFlow() async throws -> OryFlow { try makeFlow() }
    func submitRegistrationFlow(_ flow: OryFlow, values: OryFormValues, pressing action: OryInputField) async throws -> OryFlowResult<OryRegistrationResult> {
        .pending(self.flow)
    }

    func createVerificationFlow() async throws -> OryFlow { try makeFlow() }
    func getVerificationFlow(id: String) async throws -> OryFlow { try makeFlow() }
    func submitVerificationFlow(_ flow: OryFlow, values: OryFormValues, pressing action: OryInputField) async throws -> OryFlowResult<OryVerificationResult> {
        .pending(self.flow)
    }

    func createRecoveryFlow() async throws -> OryFlow { try makeFlow() }
    func submitRecoveryFlow(_ flow: OryFlow, values: OryFormValues, pressing action: OryInputField) async throws -> OryFlowResult<OryRecoveryResult> {
        .pending(self.flow)
    }

    func createSettingsFlow() async throws -> OryFlow { try makeFlow() }
    func getSettingsFlow(id: String) async throws -> OryFlow { try makeFlow() }
    func submitSettingsFlow(_ flow: OryFlow, values: OryFormValues, pressing action: OryInputField) async throws -> OryFlowResult<OrySettingsResult> {
        .pending(self.flow)
    }

    private func makeFlow() throws -> OryFlow {
        if let createFlowError { throw createFlowError }
        return flow
    }

    func deviceEnrollment() async throws -> OryDeviceEnrollmentState { deviceEnrollmentState }

    func enrollDevice(name: String, protection: OryDeviceProtection) async throws {}
    func removeDevice() async throws {}
    func removeDevice(_ device: OryEnrolledDevice) async throws {}
    func enrolledDevices() async throws -> [OryEnrolledDevice] { enrolledDevicesList }
    func forgetDevice() async throws {}

    // Sign-in / step-up are never really performed in a preview: a benign "cancelled" leaves
    // the view in its neutral state (no error banner).
    func authenticateWithDevice(pin: String?) async throws -> OryAuthenticatedSession { throw OryClientError.deviceAuthenticationCancelled }
    func loginWithDevice(pin: String?) async throws -> OryAuthenticatedSession { throw OryClientError.deviceAuthenticationCancelled }
    func resetDevicePIN(newPin: String) async throws { if let resetDevicePINError { throw resetDevicePINError } }
}
#endif
