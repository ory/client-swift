import OryClient
import SwiftUI

struct SettingsView: View {

    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
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

            case let .verification(verification):
                VerificationView(
                    viewModel: verification,
                    successMessage: "Your new address has been verified and your changes have been saved.",
                    continueTitle: "Back to settings"
                )

            case .saved:
                ContentUnavailableView {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("Your changes have been saved.")
                } actions: {
                    Button("Make another change") { Task { await viewModel.start() } }
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
        .navigationTitle("Account settings")
        .task { await viewModel.start() }
    }
}

#if DEBUG
#Preview("Form") {
    NavigationStack { SettingsView(viewModel: .preview()) }
}

#Preview("Failed") {
    NavigationStack { SettingsView(viewModel: .preview(failing: true)) }
}
#endif
