import Foundation

/// Starting and submitting registration flows.
public protocol OryRegistrationFlow: Sendable {

    /// Starts a registration flow.
    ///
    /// The returned ``OryFlow`` describes the fields to collect — the identity's traits
    /// (defined by your project's identity schema) plus a credential such as a
    /// password. Render its ``OryFlow/nodes`` and ``OryFlow/actions``, then call
    /// ``submitRegistrationFlow(_:values:pressing:)``.
    ///
    /// - Parameter options: How the flow starts. Call ``createRegistrationFlow()`` for the defaults.
    /// - Returns: A renderable registration ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func createRegistrationFlow(options: OryRegistrationFlowOptions) async throws -> OryFlow

    /// Fetches an existing registration flow by id.
    ///
    /// Use it to continue a flow the server named — for example the replacement in
    /// ``OryClientError/flowExpired(replacementFlowID:)``, which carries the message telling the
    /// user the previous attempt took too long:
    ///
    /// ```swift
    /// do {
    ///     result = try await client.submitRegistrationFlow(flow, values: values, pressing: action)
    /// } catch OryClientError.flowExpired(let replacementFlowID?) {
    ///     flow = try await client.getRegistrationFlow(id: replacementFlowID)
    /// }
    /// ```
    ///
    /// - Parameter id: The flow's id.
    /// - Returns: The renderable registration ``OryFlow``.
    /// - Throws: ``OryClientError/flowExpired(replacementFlowID:)`` when that flow expired as
    ///   well, or another ``OryClientError`` on network or server failure.
    func getRegistrationFlow(id: String) async throws -> OryFlow

    /// Submits the user's input to a registration flow.
    ///
    /// Pass the ``OryFormValues`` the user filled in and the action button they
    /// pressed. Hidden fields are included automatically.
    ///
    /// - Parameters:
    ///   - flow: The flow from ``createRegistrationFlow()`` (or a prior `.pending`).
    ///   - values: The user's entries, from ``OryFlow/makeValues()``.
    ///   - action: The submit button the user pressed, from ``OryFlow/actions``.
    /// - Returns: ``OryFlowResult/success(_:)`` with a ``OryRegistrationResult`` (whose
    ///   ``OryRegistrationResult/session`` is set, and token stored, only when the project
    ///   signs the user in after registration), or ``OryFlowResult/pending(_:)`` to
    ///   re-render.
    /// - Throws: An ``OryClientError`` on network, storage, or server failure, or
    ///   ``OryClientError/unexpectedResponse(underlying:)`` when the server reports success
    ///   without the created identity.
    func submitRegistrationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRegistrationResult>
}

extension OryRegistrationFlow {

    /// Starts a registration flow with default options.
    ///
    /// See ``createRegistrationFlow(options:)``.
    public func createRegistrationFlow() async throws -> OryFlow {
        try await createRegistrationFlow(options: OryRegistrationFlowOptions())
    }
}
