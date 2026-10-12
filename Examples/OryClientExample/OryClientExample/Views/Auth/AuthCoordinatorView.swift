import OryClient
import SwiftUI

struct AuthCoordinatorView: View {

    @StateObject private var coordinator: AuthCoordinator

    init(coordinator: @autoclosure @escaping () -> AuthCoordinator) {
        _coordinator = StateObject(wrappedValue: coordinator())
    }

    var body: some View {
        Router(
            $coordinator.path,
            withNavigation: false,
            root: {
                WelcomeView(
                    onSignIn: {
                        Task {
                            await coordinator.startSignIn()
                        }
                    },
                    onCreateAccount: { coordinator.showRegister() }
                )
            },
            destination: { page in
                switch page {
                case .login:
                    loginView
                case .pinLogin:
                    pinLoginView
                case .biometricLogin:
                    biometricLoginView
                case .register:
                    registerView
                case .recovery:
                    recoveryView
                case let .verification(handle):
                    verificationView(handle)
                case .accountCreated:
                    AccountCreatedView(onSignIn: { coordinator.continueToLogin() })
                }
            }
        )
    }

    // MARK: - Flows

    private var loginView: some View {
        LoginView(
            viewModel: LoginViewModel(
                client: coordinator.client,
                onSignedIn: { session in coordinator.didAuthenticate(session) },
                onForgotPassword: { coordinator.showRecovery() },
                onDismiss: { coordinator.dismiss() }
            )
        )
    }

    private var recoveryView: some View {
        RecoveryView(
            viewModel: RecoveryViewModel(
                client: coordinator.client,
                onFinished: { coordinator.didRecover() }
            )
        )
    }

    private var pinLoginView: some View {
        PINLoginView(
            viewModel: PINLoginViewModel(
                client: coordinator.client,
                onSignedIn: { session in coordinator.didAuthenticate(session) }
            ),
            onDismiss: { coordinator.dismiss() },
            onUseDifferentAccount: { coordinator.switchToPasswordLogin() }
        )
    }

    private var biometricLoginView: some View {
        BiometricLoginView(
            viewModel: BiometricLoginViewModel(
                client: coordinator.client,
                onSignedIn: { session in coordinator.didAuthenticate(session) }
            ),
            onDismiss: { coordinator.dismiss() },
            onUseDifferentAccount: { coordinator.switchToPasswordLogin() }
        )
    }

    private var registerView: some View {
        RegistrationView(
            viewModel: RegistrationViewModel(
                client: coordinator.client,
                onSignedIn: { session in coordinator.didAuthenticate(session) },
                onVerificationNeeded: { handle in coordinator.showVerification(handle) },
                onAccountCreated: { coordinator.showAccountCreated() },
                onDismiss: { coordinator.dismiss() }
            )
        )
    }

    private func verificationView(_ handle: OryVerificationHandle) -> some View {
        VerificationView(
            viewModel: VerificationViewModel(
                client: coordinator.client,
                existingFlowID: handle.flowID,
                onVerified: { coordinator.continueToLogin() }
            )
        )
    }
}

#if DEBUG
#Preview {
    AuthCoordinatorView(coordinator: AuthCoordinator(client: PreviewOryClient(), onAuthenticated: { _ in }, onRecovered: {}))
}
#endif
