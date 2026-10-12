import OryClient
import SwiftUI

struct RecoveryView: View {

    @State private var viewModel: RecoveryViewModel

    init(viewModel: RecoveryViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()

            case let .form(flow):
                FlowFormView(
                    flow: flow,
                    values: $viewModel.values,
                    isSubmitting: viewModel.isSubmitting,
                    submitError: viewModel.submitError
                ) { action in
                    Task { await viewModel.submit(pressing: action) }
                }

            case let .settings(settings):
                SettingsView(viewModel: settings)

            case .recovered:
                ContentUnavailableView {
                    Label("Account recovered", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("You're signed in again.")
                } actions: {
                    Button("Continue") { viewModel.finish() }
                }

            case let .failed(message):
                ContentUnavailableView {
                    Label("Something went wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.start() } }
                }
            }
        }
        .navigationTitle("Recover account")
        .task { await viewModel.start() }
    }
}

#if DEBUG
#Preview("Form") {
    NavigationStack { RecoveryView(viewModel: .preview()) }
}

#Preview("Failed") {
    NavigationStack { RecoveryView(viewModel: .preview(failing: true)) }
}
#endif
