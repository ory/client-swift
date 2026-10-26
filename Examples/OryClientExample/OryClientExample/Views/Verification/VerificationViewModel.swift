import Foundation
import Observation
import OryClient

@MainActor
@Observable
final class VerificationViewModel {

    enum State {
        case loading
        case form(OryFlow)
        case verified
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    var values = OryFormValues()

    private let client: OryClientProtocol
    private let existingFlowID: String?
    private let onVerified: () -> Void

    init(
        client: OryClientProtocol,
        existingFlowID: String? = nil,
        onVerified: @escaping () -> Void
    ) {
        self.client = client
        self.existingFlowID = existingFlowID
        self.onVerified = onVerified
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            let flow = if let existingFlowID {
                try await client.getVerificationFlow(id: existingFlowID)
            } else {
                try await client.createVerificationFlow()
            }
            apply(flow)
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
            switch try await client.submitVerificationFlow(flow, values: submitted, pressing: action) {
            case .success:
                state = .verified
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

    /// Continue once the address is verified. With "sign in after registration" off no
    /// session exists yet, so the caller routes the user to sign-in.
    func finish() {
        onVerified()
    }

    private func apply(_ flow: OryFlow) {
        values = flow.makeValues()
        submitError = nil
        state = .form(flow)
    }
}

#if DEBUG
extension VerificationViewModel {
    /// A view-only fixture: `.task` loads a sample flow (or fails when `failing` is set).
    static func preview(failing: Bool = false) -> VerificationViewModel {
        var client = PreviewOryClient()
        if failing { client.createFlowError = .server(status: 500, id: nil, messages: []) }
        return VerificationViewModel(client: client, onVerified: {})
    }
}
#endif
