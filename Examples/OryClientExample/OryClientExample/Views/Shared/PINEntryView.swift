import SwiftUI

/// A reusable PIN prompt: it collects a PIN and hands it back via `onSubmit`; the parent makes
/// the `OryClient` call and drives `isBusy`/`errorMessage`.
struct PINEntryView<Footer: View>: View {

    let title: String
    let prompt: String
    let actionTitle: String
    let isBusy: Bool
    let errorMessage: String?
    let onSubmit: (String) -> Void
    let onCancel: (() -> Void)?
    let footer: Footer

    @State private var pin = ""

    init(
        title: String,
        prompt: String,
        actionTitle: String,
        isBusy: Bool = false,
        errorMessage: String? = nil,
        onSubmit: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.prompt = prompt
        self.actionTitle = actionTitle
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text(title).font(.title2.bold())
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title2.weight(.semibold))
                .padding(.vertical, 14)
                .frame(maxWidth: 240)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                onSubmit(pin)
            } label: {
                if isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(actionTitle).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || pin.isEmpty)

            footer

            if let onCancel {
                Button("Cancel", role: .cancel) { onCancel() }
                    .disabled(isBusy)
            }
        }
        .padding(24)
    }
}

extension PINEntryView where Footer == EmptyView {
    init(
        title: String,
        prompt: String,
        actionTitle: String,
        isBusy: Bool = false,
        errorMessage: String? = nil,
        onSubmit: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            prompt: prompt,
            actionTitle: actionTitle,
            isBusy: isBusy,
            errorMessage: errorMessage,
            onSubmit: onSubmit,
            onCancel: onCancel,
            footer: { EmptyView() }
        )
    }
}

#if DEBUG
#Preview("Idle") {
    PINEntryView(title: "Choose a PIN", prompt: "Set a PIN to sign in without a password on this device.", actionTitle: "Set up", onSubmit: { _ in })
}

#Preview("Busy") {
    PINEntryView(title: "Sign in with PIN", prompt: "Enter your PIN to sign in with this device.", actionTitle: "Sign in", isBusy: true, onSubmit: { _ in })
}

#Preview("Error") {
    PINEntryView(title: "Sign in with PIN", prompt: "Enter your PIN to sign in with this device.", actionTitle: "Sign in", errorMessage: "That PIN is incorrect. Please try again.", onSubmit: { _ in })
}
#endif
