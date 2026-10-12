import Combine
import OryClient
import SwiftUI

nonisolated enum AuthPage: Hashable, Sendable {
    case login
    case pinLogin
    case biometricLogin
    case register
    case recovery
    case verification(OryVerificationHandle)
    case accountCreated
}

@MainActor
final class AuthCoordinator: CoordinatorProtocol {

    typealias Page = AuthPage

    @Published var path = RouterPath<AuthPage>()

    /// Shared with every flow the coordinator builds.
    let client: OryClientProtocol

    private let onAuthenticated: (OrySession) -> Void
    private let onRecovered: () -> Void

    init(
        client: OryClientProtocol,
        onAuthenticated: @escaping (OrySession) -> Void,
        onRecovered: @escaping () -> Void
    ) {
        self.client = client
        self.onAuthenticated = onAuthenticated
        self.onRecovered = onRecovered
    }

    // MARK: - Routing

    func showLogin() {
        presentCover(.login, withNavigation: true)
    }

    func startSignIn() async {
        // A key that verifies its holder can sign in passwordlessly; anything else uses the password.
        switch try? await client.deviceEnrollment() {
        case .enrolled(.platform):
            presentCover(.biometricLogin, withNavigation: true)
        case .enrolled(.pin):
            presentCover(.pinLogin, withNavigation: true)
        default:
            presentCover(.login, withNavigation: true)
        }
    }

    func switchToPasswordLogin() {
        dismiss()
        presentCover(.login, withNavigation: true)
    }

    func showRegister() {
        presentCover(.register, withNavigation: true)
    }

    func showRecovery() {
        push(.recovery)
    }

    func didAuthenticate(_ session: OrySession) {
        onAuthenticated(session)
    }

    /// Recovery stores a token without returning a session. Let the root re-evaluate
    /// that session, including any second-factor requirement, once settings is complete.
    func didRecover() {
        onRecovered()
    }

    func showVerification(_ handle: OryVerificationHandle) {
        push(.verification(handle))
    }

    func showAccountCreated() {
        push(.accountCreated)
    }

    func continueToLogin() {
        push(.login)
    }
}
