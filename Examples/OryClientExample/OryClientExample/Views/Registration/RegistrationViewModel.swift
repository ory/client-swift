import Foundation
import Observation
import OryClient

@MainActor
@Observable
final class RegistrationViewModel {

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
    private let onVerificationNeeded: (OryVerificationHandle) -> Void
    private let onAccountCreated: () -> Void
    private let onDismiss: () -> Void

    init(
        client: OryClientProtocol,
        onSignedIn: @escaping (OrySession) -> Void,
        onVerificationNeeded: @escaping (OryVerificationHandle) -> Void,
        onAccountCreated: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.client = client
        self.onSignedIn = onSignedIn
        self.onVerificationNeeded = onVerificationNeeded
        self.onAccountCreated = onAccountCreated
        self.onDismiss = onDismiss
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            apply(try await client.createRegistrationFlow())
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
            switch try await client.submitRegistrationFlow(flow, values: submitted, pressing: action) {
            case let .success(result):
                route(result)
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
            if let replacementFlowID {
                apply(try await client.getRegistrationFlow(id: replacementFlowID))
            } else {
                await start()
            }
        } catch {
            await start()
        }
    }

    func dismiss() {
        onDismiss()
    }

    /// Routes a successful registration. The branch depends on your project's settings:
    ///
    /// - **Sign in after registration on:** a session is issued (its token is already
    ///   stored) — go straight to the app.
    /// - **Verification required:** no session yet — verify the address first.
    /// - **Neither:** the account exists but the user still has to sign in.
    private func route(_ result: OryRegistrationResult) {
        if let session = result.session {
            onSignedIn(session.session)
        } else if let verification = result.verification {
            onVerificationNeeded(verification)
        } else {
            onAccountCreated()
        }
    }

    private func apply(_ flow: OryFlow) {
        values = flow.makeValues()
        submitError = nil
        state = .form(flow)
    }
}

#if DEBUG
extension RegistrationViewModel {
    /// A view-only fixture: `.task` loads a sample flow (or fails when `failing` is set).
    static func preview(failing: Bool = false) -> RegistrationViewModel {
        var client = PreviewOryClient()
        if failing { client.createFlowError = .server(status: 500, id: nil, messages: []) }
        return RegistrationViewModel(client: client, onSignedIn: { _ in }, onVerificationNeeded: { _ in }, onAccountCreated: {}, onDismiss: {})
    }
}
#endif
