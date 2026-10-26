import Foundation
import Observation
import OryClient

/// Drives the step-up screen. It reads how this device is enrolled with `deviceEnrollment()`,
/// then steps up with `authenticateWithDevice(pin:)` for a PIN key or `authenticateWithDevice()`
/// otherwise — each returning the upgraded AAL2 session. Without a device key it falls back to
/// a second-factor login flow (`OryLoginFlowOptions(aal: .aal2)`), which renders whatever second
/// factors the account has, such as an authenticator app code.
@MainActor
@Observable
final class SecondFactorViewModel {

    let isAvailable: Bool
    let biometryLabel: String
    private(set) var isPINEnrolled = false
    private(set) var isBiometricEnrolled = false
    private(set) var isLoaded = false
    /// The second-factor login flow, set when this device has no enrolled key.
    private(set) var secondFactorLogin: LoginViewModel?
    private(set) var isVerifying = false
    private(set) var errorMessage: String?

    private let client: OryClientProtocol
    private let onVerified: (OrySession) -> Void
    private let onCancel: () -> Void

    init(client: OryClientProtocol, onVerified: @escaping (OrySession) -> Void, onCancel: @escaping () -> Void) {
        self.client = client
        self.isAvailable = client.isDeviceAuthenticationAvailable
        self.biometryLabel = client.biometryType.label
        self.onVerified = onVerified
        self.onCancel = onCancel
    }

    func load() async {
        let enrollment = (try? await client.deviceEnrollment()) ?? .notEnrolled
        isPINEnrolled = enrollment == .enrolled(.pin)
        isBiometricEnrolled = enrollment == .enrolled(.platform)
        if enrollment == .notEnrolled {
            secondFactorLogin = LoginViewModel(
                client: client,
                options: OryLoginFlowOptions(aal: .aal2),
                onSignedIn: onVerified,
                onForgotPassword: {},
                onDismiss: onCancel
            )
        }
        isLoaded = true
    }

    /// Step up with this device's key. `OryClient` prompts biometrics for a biometric key and
    /// signs silently for a plain one.
    func verify() async {
        await run { try await self.client.authenticateWithDevice() }
    }

    /// Step up with the device PIN.
    func verify(pin: String) async {
        await run { try await self.client.authenticateWithDevice(pin: pin) }
    }

    private func run(_ operation: () async throws -> OryAuthenticatedSession) async {
        guard !isVerifying else { return }
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            let authenticated = try await operation()
            onVerified(authenticated.session)
        } catch OryClientError.deviceAuthenticationInvalidPIN {
            errorMessage = "That PIN is incorrect. Please try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        onCancel()
    }
}

#if DEBUG
extension SecondFactorViewModel {
    /// A view-only fixture: `.task` loads which factor this device is set up for.
    static func preview(enrollment: OryDeviceEnrollmentState = .enrolled(.none), available: Bool = true) -> SecondFactorViewModel {
        var client = PreviewOryClient()
        client.isDeviceAuthenticationAvailable = available
        client.deviceEnrollmentState = enrollment
        return SecondFactorViewModel(client: client, onVerified: { _ in }, onCancel: {})
    }
}
#endif
