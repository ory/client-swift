import Foundation

/// The result of a completed recovery.
///
/// Recovery signs the user into a privileged session — its token is already stored in the
/// configured ``OrySessionStorage``, so ``OryClientProtocol/currentSession()`` and the
/// follow-up settings step are authenticated. Unless the project skips it, ``settings``
/// points to the settings flow where the user must set a new password.
///
/// ```swift
/// switch try await client.submitRecoveryFlow(flow, values: values, pressing: action) {
/// case let .success(result):
///     if let settings = result.settings {
///         goToSetNewPassword(settings)   // privileged session active; set a new password
///     } else {
///         showApp()                       // recovered and signed in; no password step required
///     }
/// case let .pending(nextFlow):
///     render(nextFlow)                    // enter the emailed code, or show messages
/// @unknown default:
///     showUnsupportedStep()               // a result added in a later release
/// }
/// ```
public struct OryRecoveryResult: Sendable {

    /// The settings flow the user should complete next to choose a new password, when the
    /// project requires it. `nil` when the project skips the settings step.
    public let settings: OrySettingsHandle?

    /// Creates a recovery result. Provided for tests and previews.
    public init(settings: OrySettingsHandle?) {
        self.settings = settings
    }
}

/// A settings flow the user should be sent to next, surfaced by another flow — for example
/// recovery, which lands the user on "set a new password".
///
/// The referenced flow is already created for the user; render and submit it as a settings
/// flow.
public struct OrySettingsHandle: Sendable, Hashable {

    /// The id of the settings flow already created for the user.
    public let flowID: String

    public init(flowID: String) {
        self.flowID = flowID
    }
}
