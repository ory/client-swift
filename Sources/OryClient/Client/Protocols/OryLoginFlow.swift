import Foundation

/// Starting and submitting login flows.
public protocol OryLoginFlow: Sendable {

    /// Starts a login flow.
    ///
    /// The returned ``OryFlow`` describes the fields Ory wants you to show — which
    /// depend on your project's configuration (password, one-time code, social
    /// sign-in, …). Render its ``OryFlow/nodes`` and ``OryFlow/actions``, then call
    /// ``submitLoginFlow(_:values:pressing:)``.
    ///
    /// - Parameter options: How the flow starts. Call ``createLoginFlow()`` for the defaults.
    /// - Returns: A renderable login ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func createLoginFlow(options: OryLoginFlowOptions) async throws -> OryFlow

    /// Fetches an existing login flow by id.
    ///
    /// Use it to continue a flow the server named — for example the replacement in
    /// ``OryClientError/flowExpired(replacementFlowID:)``, which carries the message telling the
    /// user the previous attempt took too long:
    ///
    /// ```swift
    /// do {
    ///     result = try await client.submitLoginFlow(flow, values: values, pressing: action)
    /// } catch OryClientError.flowExpired(let replacementFlowID?) {
    ///     flow = try await client.getLoginFlow(id: replacementFlowID)
    /// }
    /// ```
    ///
    /// A replacement keeps the expired flow's ``OryFlow/requestedAAL`` but is never a
    /// re-authentication. When you created the expired flow with
    /// ``OryLoginFlowOptions/refresh``, compare ``OryFlow/isRefresh`` and create a new flow with
    /// your options when it is `false`.
    ///
    /// - Parameter id: The flow's id.
    /// - Returns: The renderable login ``OryFlow``.
    /// - Throws: ``OryClientError/flowExpired(replacementFlowID:)`` when that flow expired as
    ///   well, or another ``OryClientError`` on network or server failure.
    func getLoginFlow(id: String) async throws -> OryFlow

    /// Submits the user's input to a login flow.
    ///
    /// Pass the ``OryFormValues`` the user filled in and the action button they
    /// pressed. Hidden fields (CSRF tokens, nonces, internal state) are included
    /// automatically.
    ///
    /// ```swift
    /// var values = flow.makeValues()
    /// values[.identifier] = email
    /// values[.password] = password
    /// let result = try await client.submitLoginFlow(flow, values: values, pressing: action)
    /// ```
    ///
    /// - Parameters:
    ///   - flow: The flow returned by ``createLoginFlow()`` (or a prior `.pending`).
    ///   - values: The user's entries, from ``OryFlow/makeValues()``.
    ///   - action: The submit button the user pressed, from ``OryFlow/actions``.
    /// - Returns: ``OryFlowResult/success(_:)`` with the authenticated session (the
    ///   token is stored for you), or ``OryFlowResult/pending(_:)`` to re-render.
    /// - Throws: An ``OryClientError`` on network, storage, or server failure.
    func submitLoginFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryAuthenticatedSession>
}

extension OryLoginFlow {

    /// Starts a login flow with default options.
    ///
    /// See ``createLoginFlow(options:)``.
    public func createLoginFlow() async throws -> OryFlow {
        try await createLoginFlow(options: OryLoginFlowOptions())
    }
}
