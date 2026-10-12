import Foundation
import Observation
import OryClient

/// Drives the account-recovery flow (recover access by email).
///
/// Recovery is a server-driven, multi-step flow, so this view model mirrors the login and
/// verification ones: it renders whatever fields ``OryClient`` returns and submits them
/// back, re-rendering on each `.pending` step (enter your email, then the emailed code).
///
/// On success ``OryClient`` has already stored the privileged session token for you, and
/// ``OryRecoveryResult/settings`` points to the settings flow where the user sets a new
/// password. Setting the new password is a settings flow, handled by its own screen.
@MainActor
@Observable
final class RecoveryViewModel {

    enum State {
        case loading
        case form(OryFlow)
        case settings(SettingsViewModel)
        case recovered
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    var values = OryFormValues()

    private let client: OryClientProtocol
    private let onFinished: () -> Void

    init(client: OryClientProtocol, onFinished: @escaping () -> Void) {
        self.client = client
        self.onFinished = onFinished
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            apply(try await client.createRecoveryFlow())
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
            switch try await client.submitRecoveryFlow(flow, values: values, pressing: action) {
            case let .success(result):
                if let settings = result.settings {
                    state = .settings(SettingsViewModel(
                        client: client,
                        existingFlowID: settings.flowID,
                        onPasswordChanged: { [weak self] in self?.state = .recovered }
                    ))
                } else {
                    state = .recovered
                }
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

    func finish() {
        guard case .recovered = state else { return }
        onFinished()
    }

    private func apply(_ flow: OryFlow) {
        values = flow.makeValues()
        submitError = nil
        state = .form(flow)
    }
}

#if DEBUG
extension RecoveryViewModel {
    /// A view-only fixture: `.task` loads a sample flow (or fails when `failing` is set).
    static func preview(failing: Bool = false) -> RecoveryViewModel {
        var client = PreviewOryClient()
        if failing { client.createFlowError = .server(status: 500, id: nil, messages: []) }
        return RecoveryViewModel(client: client, onFinished: {})
    }
}
#endif
