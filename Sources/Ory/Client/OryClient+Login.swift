import Foundation

extension OryClient: OryLoginFlow {

    public func createLoginFlow(options: OryLoginFlowOptions) async throws -> OryFlow {
        let sessionToken = options.belongsToSession ? try await requireSessionToken() : nil
        return try await login.createLoginFlow(options: options, sessionToken: sessionToken)
    }

    public func getLoginFlow(id: String) async throws -> OryFlow {
        try await login.getLoginFlow(id: id)
    }

    public func submitLoginFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryLoginResult> {
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await login.submitLogin(
            url: body.url,
            fields: body.fields,
            sessionToken: flow.submission.sendsSessionToken ? try await requireSessionToken() : nil
        )

        switch outcome {
        case let .success(session, token, continuation):
            if let token {
                try await storeToken(token)
            }
            return .success(OryLoginResult(
                session: session,
                verification: continuation.verification,
                secondFactorEnrollment: continuation.settings
            ))

        case let .pending(flow):
            return .pending(flow)
        }
    }
}
