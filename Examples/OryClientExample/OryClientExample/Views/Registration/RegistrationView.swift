import OryClient
import SwiftUI

struct RegistrationView: View {

    @State private var viewModel: RegistrationViewModel

    init(viewModel: RegistrationViewModel) {
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
        .navigationTitle("Create account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.dismiss() }
            }
        }
        .task { await viewModel.start() }
    }
}

#if DEBUG
#Preview("Form") {
    NavigationStack { RegistrationView(viewModel: .preview()) }
}

#Preview("Failed") {
    NavigationStack { RegistrationView(viewModel: .preview(failing: true)) }
}
#endif
