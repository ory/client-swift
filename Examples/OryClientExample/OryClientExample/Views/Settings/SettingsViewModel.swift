import Foundation
import Observation
import OryClient

/// Drives the account-settings flow for the signed-in user (change password, update
/// profile, manage factors).
///
/// Like the other flows it is server-driven: ``OryClient`` returns the fields to render and
/// this view model submits them back. Two things are specific to settings: it requires a
/// signed-in session (``OryClient`` reads the stored token for you), and a sensitive change
/// on an old session throws ``OryClientError/reauthenticationRequired`` — the user is still
/// signed in, so the view model asks them to re-authenticate in a refresh login flow and then
/// retries the change.
@MainActor
@Observable
final class SettingsViewModel {

    enum State {
        case loading
        case form(OryFlow)
        case verification(VerificationViewModel)
        case saved
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    var values = OryFormValues()
    /// The re-authentication flow shown when a change needs a fresher session.
    private(set) var reauthentication: LoginViewModel?

    private let client: OryClientProtocol
    private let existingFlowID: String?
    private let onPasswordChanged: (() -> Void)?

    /// An existing flow continues recovery. Only a successful password save calls
    /// `onPasswordChanged`; saving another settings section does not complete recovery.
    init(
        client: OryClientProtocol,
        existingFlowID: String? = nil,
        onPasswordChanged: (() -> Void)? = nil
    ) {
        self.client = client
        self.existingFlowID = existingFlowID
        self.onPasswordChanged = onPasswordChanged
    }

    func start() async {
        state = .loading
        submitError = nil
        do {
            let flow = if let existingFlowID {
                try await client.getSettingsFlow(id: existingFlowID)
            } else {
                try await client.createSettingsFlow()
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
            switch try await client.submitSettingsFlow(flow, values: values, pressing: action) {
            case let .success(result):
                if let verification = result.verification {
                    state = .verification(VerificationViewModel(
                        client: client,
                        existingFlowID: verification.flowID,
                        onVerified: { [weak self] in self?.didSave(pressing: action) }
                    ))
                } else {
                    didSave(pressing: action)
                }
            case let .pending(nextFlow):
                apply(nextFlow)
            @unknown default:
                // A result added in a later OryClient release that this app does not handle yet.
                submitError = "This step isn't supported in this version of the app."
            }
        } catch OryClientError.reauthenticationRequired {
            // The session is too old for this change. The user stays signed in: confirm their
            // credential in a refresh login flow, then retry the same submit.
            reauthentication = LoginViewModel(
                client: client,
                options: OryLoginFlowOptions(refresh: true),
                onSignedIn: { [weak self] _ in
                    self?.reauthentication = nil
                    Task { await self?.submit(pressing: action) }
                },
                onForgotPassword: {},
                onDismiss: { [weak self] in self?.cancelReauthentication() }
            )
        } catch {
            submitError = error.localizedDescription
        }
    }

    func cancelReauthentication() {
        guard reauthentication != nil else { return }
        reauthentication = nil
        submitError = "This change needs you to confirm your password."
    }

    private func didSave(pressing action: OryInputField) {
        state = .saved
        if action.name == .method, action.value == "password" {
            onPasswordChanged?()
        }
    }

    private func apply(_ flow: OryFlow) {
        values = flow.makeValues()
        submitError = nil
        state = .form(flow)
    }
}

#if DEBUG
extension SettingsViewModel {
    /// A view-only fixture: `.task` loads a sample flow (or fails when `failing` is set).
    static func preview(failing: Bool = false) -> SettingsViewModel {
        var client = PreviewOryClient()
        if failing { client.createFlowError = .server(status: 500, id: nil, messages: []) }
        return SettingsViewModel(client: client)
    }
}
#endif
