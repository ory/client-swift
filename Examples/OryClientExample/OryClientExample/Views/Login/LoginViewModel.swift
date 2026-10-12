import Foundation
import Observation
import OryClient

@MainActor
@Observable
final class LoginViewModel {

    enum State {
        case loading
        case form(OryFlow)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    var values = OryFormValues()

    private let client: OryClientProtocol
    private let onSignedIn: (OrySession) -> Void
    private let onForgotPassword: () -> Void
    private let onDismiss: () -> Void

    init(
        client: OryClientProtocol,
        onSignedIn: @escaping (OrySession) -> Void,
        onForgotPassword: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.client = client
        self.onSignedIn = onSignedIn
        self.onForgotPassword = onForgotPassword
        self.onDismiss = onDismiss
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            apply(try await client.createLoginFlow())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func submit(pressing action: OryInputField) async {
        guard case let .form(flow) = state, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            switch try await client.submitLoginFlow(flow, values: values, pressing: action) {
            case let .success(authenticated):
                onSignedIn(authenticated.session)
            case let .pending(nextFlow):
                apply(nextFlow)
            @unknown default:
                // A result added in a later OryClient release that this app does not handle yet.
                submitError = "This step isn't supported in this version of the app."
            }
        } catch {
            submitError = error.localizedDescription
        }
    }

    func forgotPassword() {
        onForgotPassword()
    }

    func dismiss() {
        onDismiss()
    }

    private func apply(_ flow: OryFlow) {
        values = flow.makeValues()
        submitError = nil
        state = .form(flow)
    }
}

#if DEBUG
extension LoginViewModel {
    /// A view-only fixture: `.task` loads a sample flow (or fails when `failing` is set).
    static func preview(failing: Bool = false) -> LoginViewModel {
        var client = PreviewOryClient()
        if failing { client.createFlowError = .server(status: 500, id: nil, messages: []) }
        return LoginViewModel(client: client, onSignedIn: { _ in }, onForgotPassword: {}, onDismiss: {})
    }
}
#endif
