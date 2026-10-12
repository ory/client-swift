import OryClient
import SwiftUI

struct RootView: View {

    @State private var viewModel: RootViewModel

    init(viewModel: RootViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        stateContent
            .task { await viewModel.onTask() }
    }

    @ViewBuilder private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()

        case let .signedIn(session):
            SignedInView(
                session: session,
                client: viewModel.client,
                onSessionChanged: { viewModel.didCompleteSecondFactor($0) },
                onRefresh: { await viewModel.refreshSession() },
                onSignOut: { Task { await viewModel.signOut() } }
            )

        case .needsSecondFactor:
            SecondFactorView(
                viewModel: SecondFactorViewModel(
                    client: viewModel.client,
                    onVerified: { viewModel.didCompleteSecondFactor($0) },
                    onCancel: { Task { await viewModel.signOut() } }
                )
            )

        case let .pinLockedRecovery(session):
            PINRecoveryView(
                viewModel: PINRecoveryViewModel(
                    client: viewModel.client,
                    session: session,
                    onRecovered: { viewModel.didFinishRecovery($0) },
                    onSkip: { viewModel.didFinishRecovery($0) }
                )
            )

        case .signedOut:
            AuthCoordinatorView(
                coordinator: AuthCoordinator(
                    client: viewModel.client,
                    onAuthenticated: { session in Task { await viewModel.didAuthenticate(session) } },
                    onRecovered: { Task { await viewModel.onTask() } }
                )
            )
        }
    }
}

#if DEBUG
#Preview("Signed in") {
    RootView(viewModel: .preview(.success(PreviewData.session(aal: .aal2))))
}

#Preview("Second factor") {
    RootView(viewModel: .preview(.failure(.secondFactorRequired)))
}

#Preview("PIN locked recovery") {
    RootView(viewModel: .preview(.success(PreviewData.session(aal: .aal1)), lockedCurrentDevice: true))
}

#Preview("Signed out") {
    RootView(viewModel: .preview(.failure(.notAuthenticated)))
}
#endif
