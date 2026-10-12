import SwiftUI

struct PINLoginView: View {

    @State private var viewModel: PINLoginViewModel
    private let onDismiss: () -> Void
    private let onUseDifferentAccount: () -> Void

    init(
        viewModel: PINLoginViewModel,
        onDismiss: @escaping () -> Void,
        onUseDifferentAccount: @escaping () -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDismiss = onDismiss
        self.onUseDifferentAccount = onUseDifferentAccount
    }

    var body: some View {
        PINEntryView(
            title: "Sign in with PIN",
            prompt: "Enter your PIN to sign in with this device.",
            actionTitle: "Sign in",
            isBusy: viewModel.isBusy,
            errorMessage: viewModel.errorMessage,
            onSubmit: { pin in Task { await viewModel.login(pin: pin) } },
            footer: {
                if viewModel.isLikelyLocked {
                    // After too many failures the key is probably locked, so retrying the PIN
                    // cannot help. Promote password sign-in to the primary way forward — it is
                    // what lets the user reach the PIN reset once signed in.
                    Button("Sign in with password") { onUseDifferentAccount() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(viewModel.isBusy)
                } else {
                    Button("Sign in to a different account") { onUseDifferentAccount() }
                        .font(.footnote)
                        .disabled(viewModel.isBusy)
                }
            }
        )
        .navigationTitle("PIN sign-in")
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
#Preview("Idle") {
    NavigationStack { PINLoginView(viewModel: .preview(), onDismiss: {}, onUseDifferentAccount: {}) }
}

#Preview("Error") {
    NavigationStack {
        PINLoginView(viewModel: .preview(errorMessage: "That PIN is incorrect. Please try again."), onDismiss: {}, onUseDifferentAccount: {})
    }
}

#Preview("Likely locked") {
    NavigationStack {
        PINLoginView(
            viewModel: .preview(errorMessage: "Too many incorrect attempts. Your PIN may be locked. Sign in with your password to reset it.", locked: true),
            onDismiss: {},
            onUseDifferentAccount: {}
        )
    }
}
#endif
