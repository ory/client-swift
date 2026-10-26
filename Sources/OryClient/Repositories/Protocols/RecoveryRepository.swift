import Foundation

/// The recovery flow's data operations.
protocol RecoveryRepository: Sendable {

    /// Creates a native recovery flow and maps it to a renderable ``OryFlow``.
    func createRecoveryFlow() async throws -> OryFlow

    func getRecoveryFlow(id: String) async throws -> OryFlow

    /// Submits the merged form to a recovery flow's action URL.
    func submitRecovery(url: URL, fields: [String: String]) async throws -> RecoveryOutcome
}

/// The internal outcome of submitting a recovery flow.
///
/// Recovery is multi-step and state-driven: the server returns the flow at each step, and
/// success is signaled by its state (`passed_challenge`) rather than an HTTP status. On
/// success it also issues a privileged session (its token) and, unless the project skips
/// it, points to a settings flow where the user sets a new password.
enum RecoveryOutcome: Sendable {

    /// The flow passed the challenge. `token` is the privileged session token, when the
    /// server issued one; `settingsFlowID` is the settings flow to set a new password,
    /// when the project requires that step.
    case completed(token: String?, settingsFlowID: String?)

    /// A further step or a validation error; re-render the flow (e.g. enter the emailed
    /// code, or show messages).
    case pending(OryFlow)
}
