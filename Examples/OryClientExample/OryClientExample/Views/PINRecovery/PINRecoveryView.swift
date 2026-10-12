import SwiftUI

/// The guided step shown right after sign-in when this device's PIN is locked. It reuses
/// ``PINEntryView`` to collect a new PIN and hands the reset to ``PINRecoveryViewModel``;
/// "Not now" lets the user into the app and reset later from two-factor settings.
struct PINRecoveryView: View {

    @State private var viewModel: PINRecoveryViewModel

    init(viewModel: PINRecoveryViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        PINEntryView(
            title: "Your PIN is locked",
            prompt: "Too many incorrect attempts locked PIN sign-in on this device. Set a new PIN to use it again — you don't need your old one.",
            actionTitle: "Set new PIN",
            isBusy: viewModel.isBusy,
            errorMessage: viewModel.errorMessage,
            onSubmit: { pin in Task { await viewModel.resetPIN(pin) } },
            footer: {
                Button("Not now") { viewModel.skip() }
                    .font(.footnote)
                    .disabled(viewModel.isBusy)
            }
        )
    }
}

#if DEBUG
#Preview("Idle") {
    PINRecoveryView(viewModel: .preview())
}

#Preview("Error") {
    PINRecoveryView(viewModel: .preview(errorMessage: "This device is no longer set up for PIN sign-in. Set up a PIN again from the two-factor settings."))
}
#endif
