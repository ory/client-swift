import Foundation

/// The settings flow's data operations. All are authenticated with the session token.
protocol SettingsRepository: Sendable {

    /// Creates a native settings flow and maps it to a renderable ``OryFlow``.
    func createSettingsFlow(sessionToken: String) async throws -> OryFlow

    /// Fetches an existing settings flow by id (e.g. the one recovery created).
    func getSettingsFlow(id: String, sessionToken: String) async throws -> OryFlow

    /// Submits the merged form to a settings flow's action URL.
    func submitSettings(url: URL, fields: [String: String], sessionToken: String) async throws -> SettingsOutcome
}

/// The internal outcome of submitting a settings flow.
///
/// Settings is state-driven: the server returns the flow, and a change is applied when its
/// state is `success` (HTTP 200). A `400` re-renders the flow with validation errors.
/// A verification continuation takes precedence over the state on a successful response.
/// A change that needs a fresher session surfaces as ``OryClientError/reauthenticationRequired``
/// (thrown, not returned here).
enum SettingsOutcome: Sendable {

    /// The submission was accepted. A verification handle means the change still needs
    /// confirmation and the identity contains the current, unchanged traits.
    case completed(OryIdentity, verification: OryVerificationHandle? = nil)

    /// Validation errors or a further step; re-render the flow.
    case pending(OryFlow)
}
