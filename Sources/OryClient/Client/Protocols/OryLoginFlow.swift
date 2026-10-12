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
    /// - Returns: A renderable login ``OryFlow``.
    /// - Throws: An ``OryClientError`` on network or server failure.
    func createLoginFlow() async throws -> OryFlow

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
