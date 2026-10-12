import OryClient
import SwiftUI

struct LoginView: View {

    @State private var viewModel: LoginViewModel

    init(viewModel: LoginViewModel) {
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
                .safeAreaInset(edge: .bottom) {
                    Button("Forgot password?") { viewModel.forgotPassword() }
                        .padding()
                        .disabled(viewModel.isSubmitting)
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
        .navigationTitle("Sign in")
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
    NavigationStack { LoginView(viewModel: .preview()) }
}

#Preview("Failed") {
    NavigationStack { LoginView(viewModel: .preview(failing: true)) }
}
#endif
