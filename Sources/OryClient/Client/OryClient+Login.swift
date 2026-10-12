import Foundation

extension OryClient: OryLoginFlow {

    public func createLoginFlow() async throws -> OryFlow {
        try await login.createLoginFlow()
    }

    public func submitLoginFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryAuthenticatedSession> {
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await login.submitLogin(
            url: body.url,
            fields: body.fields,
            sessionToken: nil
        )

        switch outcome {
        case let .success(session, token):
            if let token {
                try await storeToken(token)
            }
            return .success(OryAuthenticatedSession(session: session))

        case let .pending(flow):
            return .pending(flow)
        }
    }
}
