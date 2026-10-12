import Foundation

/// Starting, fetching, and submitting verification flows.
public protocol OryVerificationFlow: Sendable {

    /// Starts a verification flow (to verify an email or phone).
    ///
    /// - Returns: A renderable verification ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func createVerificationFlow() async throws -> OryFlow

    /// Fetches an existing verification flow by id — for example the one a registration
    /// surfaced in ``OryRegistrationResult/verification``.
    ///
    /// - Parameter id: The ``OryVerificationHandle/flowID``.
    /// - Returns: The renderable verification ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func getVerificationFlow(id: String) async throws -> OryFlow

    /// Submits the user's input to a verification flow.
    ///
    /// Verification is multi-step: submitting the address sends a code, and submitting
    /// the code verifies it. Each step returns ``OryFlowResult/pending(_:)`` to
    /// re-render (now showing the code field, or messages); a completed verification
    /// returns ``OryFlowResult/success(_:)``.
    ///
    /// - Parameters:
    ///   - flow: The flow from ``createVerificationFlow()`` / ``getVerificationFlow(id:)``
    ///     (or a prior `.pending`).
    ///   - values: The user's entries, from ``OryFlow/makeValues()``.
    ///   - action: The submit button the user pressed, from ``OryFlow/actions``.
    /// - Returns: ``OryFlowResult/success(_:)`` when verified, or
    ///   ``OryFlowResult/pending(_:)`` for the next step.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func submitVerificationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryVerificationResult>
}
