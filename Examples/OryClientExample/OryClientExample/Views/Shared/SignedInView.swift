import OryClient
import SwiftUI

struct SignedInView: View {

    let session: OrySession
    let client: OryClientProtocol
    let onSessionChanged: (OrySession) -> Void
    let onRefresh: () async -> Void
    let onSignOut: () -> Void

    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Session ID", value: session.id)
                    LabeledContent("Active", value: session.isActive ? "Yes" : "No")
                    LabeledContent("Assurance", value: session.authenticatorAssuranceLevel.rawValue)
                    if let identity = session.identity {
                        LabeledContent("Identity ID", value: identity.id)
                    }
                    if let expiresAt = session.expiresAt {
                        LabeledContent("Expires", value: expiresAt.formatted())
                    }
                    Button {
                        Task {
                            isRefreshing = true
                            await onRefresh()
                            isRefreshing = false
                        }
                    } label: {
                        HStack {
                            Text("Refresh session info")
                            if isRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                }

                Section("Account") {
                    NavigationLink("Account settings") {
                        SettingsView(viewModel: SettingsViewModel(client: client))
                    }
                }

                Section("Security") {
                    NavigationLink("Two-factor authentication") {
                        DeviceAuthnView(
                            viewModel: DeviceAuthnViewModel(
                                client: client,
                                session: session,
                                onSessionChanged: onSessionChanged
                            )
                        )
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) { onSignOut() }
                }
            }
            .navigationTitle("Signed in")
        }
    }
}

#if DEBUG
#Preview {
    SignedInView(
        session: PreviewData.session(aal: .aal2),
        client: PreviewOryClient(),
        onSessionChanged: { _ in },
        onRefresh: {},
        onSignOut: {}
    )
}
#endif
