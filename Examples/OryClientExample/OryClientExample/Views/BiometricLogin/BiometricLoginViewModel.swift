import Foundation
import Observation
import OryClient

/// Drives passwordless sign-in with device biometrics (first factor). One call —
/// ``OryDeviceLogin/loginWithDevice()`` — prompts Face ID / Touch ID, signs the server
/// challenge, and returns a session; the view model maps failures to user-facing text.
@MainActor
@Observable
final class BiometricLoginViewModel {

    let biometryLabel: String
    let biometrySystemImage: String
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let client: OryClientProtocol
    private let onSignedIn: (OrySession) -> Void

    init(client: OryClientProtocol, onSignedIn: @escaping (OrySession) -> Void) {
        self.client = client
        self.biometryLabel = client.biometryType.label
        self.biometrySystemImage = client.biometryType.systemImage
        self.onSignedIn = onSignedIn
    }

    func login() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let authenticated = try await client.loginWithDevice()
            onSignedIn(authenticated.session)
        } catch OryClientError.deviceAuthenticationCancelled {
            // The user dismissed the prompt — no error, let them tap the button to retry.
            errorMessage = nil
        } catch OryClientError.deviceAuthenticationBiometricsChanged {
            // A face or fingerprint was added or removed since enrollment, so this key can never
            // be used again. Forget it locally so the app stops offering biometric sign-in; the
            // user signs in with their password and can set biometrics up again from settings.
            try? await client.forgetDevice()
            errorMessage = "\(biometryLabel) changed on this device. Sign in with your password, then set up \(biometryLabel) again in settings."
        } catch OryClientError.deviceAuthenticationNotEnrolled {
            errorMessage = "\(biometryLabel) sign-in isn't set up on this device. Sign in with your password, then enable it in settings."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
extension BiometricLoginViewModel {
    /// A view-only fixture: picks the biometry to label the button, optionally pre-populated
    /// with an error message.
    static func preview(biometry: OryBiometryType = .faceID, errorMessage: String? = nil) -> BiometricLoginViewModel {
        var client = PreviewOryClient()
        client.biometryType = biometry
        let viewModel = BiometricLoginViewModel(client: client, onSignedIn: { _ in })
        viewModel.errorMessage = errorMessage
        return viewModel
    }
}
#endif
