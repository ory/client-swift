import SwiftUI

struct AccountCreatedView: View {

    let onSignIn: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Account created", systemImage: "checkmark.seal")
        } description: {
            Text("Your account is ready. Sign in to continue.")
        } actions: {
            Button("Sign in") { onSignIn() }
        }
        .navigationTitle("Done")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AccountCreatedView(onSignIn: {})
    }
}
#endif
