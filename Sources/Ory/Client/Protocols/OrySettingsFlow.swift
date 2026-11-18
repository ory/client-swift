import Foundation

/// Managing the signed-in user's account settings: change password, update profile traits,
/// and manage authentication factors. Every call requires a signed-in session.
public protocol OrySettingsFlow: Sendable {

    /// Starts a settings flow for the signed-in user.
    ///
    /// - Parameter options: How the flow starts. Call ``createSettingsFlow()`` for the defaults.
    /// - Returns: A renderable settings ``OryFlow``.
    /// - Throws: ``OryClientError/notAuthenticated`` when no session is stored, or another
    ///   ``OryClientError`` on network or server failure.
    func createSettingsFlow(options: OrySettingsFlowOptions) async throws -> OryFlow

    /// Fetches an existing settings flow by id — for example the one recovery surfaced in
    /// ``OryRecoveryResult/settings`` to set a new password.
    ///
    /// - Parameter id: The ``OrySettingsHandle/flowID``.
    /// - Returns: The renderable settings ``OryFlow``.
    /// - Throws: ``OryClientError/notAuthenticated`` when no session is stored, or another
    ///   ``OryClientError`` on network or server failure.
    func getSettingsFlow(id: String) async throws -> OryFlow

    /// Submits the user's input to a settings flow.
    ///
    /// A settings flow can offer several sections (password, profile, TOTP, …). Submit the
    /// fields for the section the user changed, selecting its action. A validation error
    /// returns ``OryFlowResult/pending(_:)`` to re-render; a saved change returns
    /// ``OryFlowResult/success(_:)`` with the updated identity. When the project asks the
    /// user to verify a changed address, `.success` also carries
    /// ``OrySettingsResult/verification``. Depending on the project, the change is applied
    /// once that verification completes or is already saved with the new address unverified;
    /// see ``OrySettingsResult/identity``. Complete the verification flow either way.
    ///
    /// - Parameters:
    ///   - flow: The flow from ``createSettingsFlow()`` / ``getSettingsFlow(id:)`` (or a
    ///     prior `.pending`).
    ///   - values: The user's entries, from ``OryFlow/makeValues()``.
    ///   - action: The submit button the user pressed, from ``OryFlow/actions``.
    /// - Returns: ``OryFlowResult/success(_:)`` when saved or handed off to verification,
    ///   or ``OryFlowResult/pending(_:)`` to re-render validation errors or another settings step.
    /// - Throws: ``OryClientError/reauthenticationRequired`` when the change needs a fresher
    ///   session — the user is still signed in, so prove the credential again (for example
    ///   ``OryDeviceStepUp/authenticateWithDevice(pin:)``) and retry —
    ///   ``OryClientError/notAuthenticated`` when no session is stored, or another
    ///   ``OryClientError`` on network or server failure.
    func submitSettingsFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OrySettingsResult>
}

extension OrySettingsFlow {

    /// Starts a settings flow with default options.
    ///
    /// See ``createSettingsFlow(options:)``.
    public func createSettingsFlow() async throws -> OryFlow {
        try await createSettingsFlow(options: OrySettingsFlowOptions())
    }
}
