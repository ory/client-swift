import Foundation
import Observation
import OryClient

/// Drives the guided recovery shown after the user signs in another way (e.g. with a password)
/// while this device's PIN is locked.
///
/// Recovery is a single call — ``OryClientProtocol/resetDevicePIN(newPin:)`` — which re-issues
/// the device's PIN secret by proving device possession (a silent device-signature step), so the
/// old, locked PIN is never needed. A locked key no longer counts as a second factor, which is
/// what lets the plain first-factor session reach this settings change. On success the user can
/// sign in with the new PIN again.
@MainActor
@Observable
final class PINRecoveryViewModel {

    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let client: OryClientProtocol
    private let session: OrySession
    private let onRecovered: (OrySession) -> Void
    private let onSkip: (OrySession) -> Void

    init(
        client: OryClientProtocol,
        session: OrySession,
        onRecovered: @escaping (OrySession) -> Void,
        onSkip: @escaping (OrySession) -> Void
    ) {
        self.client = client
        self.session = session
        self.onRecovered = onRecovered
        self.onSkip = onSkip
    }

    /// Validates a chosen PIN against this app's policy before resetting. `OryClient` performs no
    /// PIN validation — the server never sees the PIN — so this is where the integrating app
    /// enforces its own rules (see ``PINValidator``). Returns a user-facing error, or `nil`.
    func pinValidationError(for pin: String) -> String? {
        PINValidator(pin: pin).execute().firstErrorMessage
    }

    func resetPIN(_ newPin: String) async {
        guard !isBusy else { return }
        if let validationError = pinValidationError(for: newPin) {
            errorMessage = validationError
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.resetDevicePIN(newPin: newPin)
            onRecovered(session)
        } catch OryClientError.deviceAuthenticationNotEnrolled {
            errorMessage = "This device is no longer set up for PIN sign-in. Set up a PIN again from the two-factor settings."
        } catch OryClientError.secondFactorRequired {
            // Only reachable if the key still counts as a second factor (i.e. it is not actually
            // locked). Recovery cannot supply the second factor here, so send the user to the
            // settings screen where a normal reset can step up.
            errorMessage = "This device still needs a second factor. Open two-factor settings to reset the PIN."
        } catch OryClientError.reauthenticationRequired {
            errorMessage = "For your security, sign in again before resetting your PIN."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skip() {
        onSkip(session)
    }
}

#if DEBUG
extension PINRecoveryViewModel {
    /// A view-only fixture, optionally pre-populated with an error message.
    static func preview(errorMessage: String? = nil) -> PINRecoveryViewModel {
        let viewModel = PINRecoveryViewModel(
            client: PreviewOryClient(),
            session: PreviewData.session(aal: .aal1),
            onRecovered: { _ in },
            onSkip: { _ in }
        )
        viewModel.errorMessage = errorMessage
        return viewModel
    }
}
#endif
