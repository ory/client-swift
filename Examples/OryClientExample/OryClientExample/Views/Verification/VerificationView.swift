import OryClient
import SwiftUI

struct VerificationView: View {

    @State private var viewModel: VerificationViewModel
    private let successMessage: String
    private let continueTitle: String

    init(
        viewModel: VerificationViewModel,
        successMessage: String = "Your address has been verified. Sign in to finish.",
        continueTitle: String = "Continue to sign in"
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.successMessage = successMessage
        self.continueTitle = continueTitle
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

            case .verified:
                ContentUnavailableView {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                } description: {
                    Text(successMessage)
                } actions: {
                    Button(continueTitle) { viewModel.finish() }
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
        .navigationTitle("Verify")
        .task { await viewModel.start() }
    }
}

#if DEBUG
#Preview("Form") {
    NavigationStack { VerificationView(viewModel: .preview()) }
}

#Preview("Failed") {
    NavigationStack { VerificationView(viewModel: .preview(failing: true)) }
}
#endif
