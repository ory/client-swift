import OryClient
import SwiftUI

struct SecondFactorView: View {

    @State private var viewModel: SecondFactorViewModel

    init(viewModel: SecondFactorViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if !viewModel.isLoaded {
                ProgressView()
            } else if let secondFactorLogin = viewModel.secondFactorLogin {
                NavigationStack { LoginView(viewModel: secondFactorLogin) }
            } else if viewModel.isPINEnrolled {
                PINEntryView(
                    title: "Verify it's you",
                    prompt: "Enter your PIN to verify this device and continue.",
                    actionTitle: "Verify",
                    isBusy: viewModel.isVerifying,
                    errorMessage: viewModel.errorMessage,
                    onSubmit: { pin in Task { await viewModel.verify(pin: pin) } },
                    onCancel: { viewModel.cancel() }
                )
            } else {
                deviceVerification
            }
        }
        .task { await viewModel.load() }
    }

    private var deviceVerification: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Verify it's you")
                .font(.title2.bold())

            Text("Your account requires a second factor. Verify with the key on this device to continue.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                Task { await viewModel.verify() }
            } label: {
                if viewModel.isVerifying {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.isBiometricEnrolled ? "Verify with \(viewModel.biometryLabel)" : "Verify this device")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isVerifying || !viewModel.isAvailable)

            Button("Sign out", role: .cancel) {
                viewModel.cancel()
            }
            .disabled(viewModel.isVerifying)
        }
        .padding(24)
    }
}

#if DEBUG
#Preview("Device") {
    SecondFactorView(viewModel: .preview())
}

#Preview("Biometric") {
    SecondFactorView(viewModel: .preview(enrollment: .enrolled(.platform)))
}

#Preview("PIN") {
    SecondFactorView(viewModel: .preview(enrollment: .enrolled(.pin)))
}
#endif
