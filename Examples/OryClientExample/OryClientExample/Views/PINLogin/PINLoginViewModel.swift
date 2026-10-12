import Foundation
import Observation
import OryClient

/// Drives passwordless sign-in with the device PIN (first factor). One call —
/// ``OryDeviceLogin/loginWithDevice(pin:)`` — unlocks the device secret with the PIN,
/// signs the server challenge, and returns a session; the view model just maps failures to
/// user-facing text.
@MainActor
@Observable
final class PINLoginViewModel {

    /// How many wrong PINs this screen tolerates before it stops inviting retries and steers the
    /// user to password sign-in. Set this to your project's configured `max_attempts`: once the
    /// server has locked the device key, every further attempt — even the correct PIN — returns
    /// the same generic error, so retrying cannot succeed.
    ///
    /// This is a client-side heuristic only. The login response is deliberately identical for a
    /// wrong PIN and a locked key (anti-enumeration), so the app cannot know here that the key is
    /// locked; it only knows the user has failed enough times to be worth redirecting. The
    /// authoritative locked state is read after signing in another way, from
    /// ``OryEnrolledDevice/isLocked`` (see `RootViewModel`).
    private let maxAttemptsBeforeLockoutHint = 3

    let isAvailable: Bool
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    /// `true` once the user has failed enough times that the key is probably locked. The view
    /// uses it to promote "Sign in with password" to the primary action.
    private(set) var isLikelyLocked = false

    private var failedAttempts = 0

    private let client: OryClientProtocol
    private let onSignedIn: (OrySession) -> Void

    init(client: OryClientProtocol, onSignedIn: @escaping (OrySession) -> Void) {
        self.client = client
        self.isAvailable = client.isDeviceAuthenticationAvailable
        self.onSignedIn = onSignedIn
    }

    func login(pin: String) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let authenticated = try await client.loginWithDevice(pin: pin)
            onSignedIn(authenticated.session)
        } catch OryClientError.deviceAuthenticationInvalidPIN {
            failedAttempts += 1
            if failedAttempts >= maxAttemptsBeforeLockoutHint {
                isLikelyLocked = true
                errorMessage = "Too many incorrect attempts. Your PIN may be locked. Sign in with your password to reset it."
            } else {
                errorMessage = "That PIN is incorrect. Please try again."
            }
        } catch OryClientError.deviceAuthenticationNotEnrolled {
            errorMessage = "PIN sign-in isn't set up on this device. Sign in with your password, then enable it in settings."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
extension PINLoginViewModel {
    /// A view-only fixture, optionally pre-populated with an error message and the locked hint.
    static func preview(errorMessage: String? = nil, locked: Bool = false) -> PINLoginViewModel {
        let viewModel = PINLoginViewModel(client: PreviewOryClient(), onSignedIn: { _ in })
        viewModel.errorMessage = errorMessage
        viewModel.isLikelyLocked = locked
        return viewModel
    }
}
#endif
