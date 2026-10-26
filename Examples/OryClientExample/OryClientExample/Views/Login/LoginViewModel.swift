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
    private let options: OryLoginFlowOptions
    private let onSignedIn: (OrySession) -> Void
    private let onForgotPassword: () -> Void
    private let onDismiss: () -> Void

    /// `options` selects the kind of login: the default signs a user in, while
    /// `OryLoginFlowOptions(refresh: true)` re-authenticates and `OryLoginFlowOptions(aal: .aal2)`
    /// asks for a second factor — both for the user who is already signed in.
    init(
        client: OryClientProtocol,
        options: OryLoginFlowOptions = OryLoginFlowOptions(),
        onSignedIn: @escaping (OrySession) -> Void,
        onForgotPassword: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.client = client
        self.options = options
        self.onSignedIn = onSignedIn
        self.onForgotPassword = onForgotPassword
        self.onDismiss = onDismiss
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            apply(try await client.createLoginFlow(options: options))
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
            // "Resend code" asks for a new code, so it is sent without the code the user typed.
            let submitted = action == flow.resendCodeAction ? flow.makeValues() : values
            switch try await client.submitLoginFlow(flow, values: submitted, pressing: action) {
            case let .success(authenticated):
                onSignedIn(authenticated.session)
            case let .pending(nextFlow):
                apply(nextFlow)
            @unknown default:
                // A result added in a later OryClient release that this app does not handle yet.
                submitError = "This step isn't supported in this version of the app."
            }
        } catch OryClientError.flowExpired(let replacementFlowID) {
            // The user took too long. Continue with the flow the server prepared — it explains
            // what happened — or start a new one when it named none.
            await restart(replacementFlowID: replacementFlowID)
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func restart(replacementFlowID: String?) async {
        do {
            guard let replacementFlowID else { return await start() }
            let replacement = try await client.getLoginFlow(id: replacementFlowID)
            // The server does not carry `refresh` into a replacement, so a re-authentication
            // would continue as a different operation. Start over with this screen's options.
            guard replacement.isRefresh == options.refresh else { return await start() }
            apply(replacement)
        } catch {
            await start()
        }
    }

    /// Re-authentication and second-factor flows confirm the signed-in user instead of signing
    /// someone in, so the screen is titled differently and offers no password recovery.
    var confirmsSignedInUser: Bool {
        options.refresh || options.aal == .aal2
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
