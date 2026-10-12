import OryClient
import SwiftUI

struct BiometricLoginView: View {

    @State private var viewModel: BiometricLoginViewModel
    private let onDismiss: () -> Void
    private let onUseDifferentAccount: () -> Void

    init(
        viewModel: BiometricLoginViewModel,
        onDismiss: @escaping () -> Void,
        onUseDifferentAccount: @escaping () -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDismiss = onDismiss
        self.onUseDifferentAccount = onUseDifferentAccount
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: viewModel.biometrySystemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Sign in with \(viewModel.biometryLabel)")
                .font(.title2.bold())
            Text("Use \(viewModel.biometryLabel) to sign in on this device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                Task { await viewModel.login() }
            } label: {
                if viewModel.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with \(viewModel.biometryLabel)").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy)

            Button("Sign in to a different account") { onUseDifferentAccount() }
                .font(.footnote)
                .disabled(viewModel.isBusy)
        }
        .controlSize(.large)
        .padding()
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { onDismiss() }
                    .disabled(viewModel.isBusy)
            }
        }
    }
}

#if DEBUG
#Preview("Face ID") {
    NavigationStack { BiometricLoginView(viewModel: .preview(biometry: .faceID), onDismiss: {}, onUseDifferentAccount: {}) }
}

#Preview("Touch ID") {
    NavigationStack { BiometricLoginView(viewModel: .preview(biometry: .touchID), onDismiss: {}, onUseDifferentAccount: {}) }
}

#Preview("Not set up") {
    NavigationStack {
        BiometricLoginView(
            viewModel: .preview(errorMessage: "Face ID sign-in isn't set up on this device."),
            onDismiss: {},
            onUseDifferentAccount: {}
        )
    }
}
#endif
