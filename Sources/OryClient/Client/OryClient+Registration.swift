import Foundation

extension OryClient: OryRegistrationFlow {

    public func createRegistrationFlow(options: OryRegistrationFlowOptions) async throws -> OryFlow {
        try await registration.createRegistrationFlow()
    }

    public func getRegistrationFlow(id: String) async throws -> OryFlow {
        try await registration.getRegistrationFlow(id: id)
    }

    public func submitRegistrationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRegistrationResult> {
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await registration.submitRegistration(
            url: body.url,
            fields: body.fields,
            sessionToken: nil
        )

        switch outcome {
        case let .success(identity, session, token, verification):
            if let token {
                try await storeToken(token)
            }
            let authenticated = session.map { OryAuthenticatedSession(session: $0) }
            return .success(OryRegistrationResult(identity: identity, session: authenticated, verification: verification))

        case let .pending(flow):
            return .pending(flow)
        }
    }
}
