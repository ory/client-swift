import Foundation

/// Starting and submitting recovery flows — recovering access to an account, typically by
/// email.
public protocol OryRecoveryFlow: Sendable {

    /// Starts a recovery flow.
    ///
    /// - Returns: A renderable recovery ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func createRecoveryFlow() async throws -> OryFlow

    /// Submits the user's input to a recovery flow.
    ///
    /// Recovery is multi-step: submitting the address sends a code, and submitting the code
    /// completes recovery. Each intermediate step returns ``OryFlowResult/pending(_:)`` to
    /// re-render (now showing the code field, or messages). On success the user is signed
    /// into a privileged session — its token is stored for you — and
    /// ``OryFlowResult/success(_:)`` carries an ``OryRecoveryResult`` whose
    /// ``OryRecoveryResult/settings`` handle points to the settings flow for setting a new
    /// password.
    ///
    /// The project must enable the `use_continue_with_transitions` feature flag. Without it
    /// the server cannot hand the session to a native app, and the final step throws
    /// ``OryClientError/server(status:id:messages:)`` with status 422.
    ///
    /// - Parameters:
    ///   - flow: The flow from ``createRecoveryFlow()`` (or a prior `.pending`).
    ///   - values: The user's entries, from ``OryFlow/makeValues()``.
    ///   - action: The submit button the user pressed, from ``OryFlow/actions``.
    /// - Returns: ``OryFlowResult/success(_:)`` when recovered, or
    ///   ``OryFlowResult/pending(_:)`` for the next step.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func submitRecoveryFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRecoveryResult>
}
