import SwiftUI

struct WelcomeView: View {

    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.badge.key")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Ory Example")
                .font(.largeTitle.bold())
            Text("Sign in or create an account to continue.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: onSignIn) {
                Text("Sign in").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onCreateAccount) {
                Text("Create account").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding()
    }
}

#Preview {
    WelcomeView(onSignIn: {}, onCreateAccount: {})
}
