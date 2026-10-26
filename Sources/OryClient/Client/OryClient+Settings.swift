import Foundation

extension OryClient: OrySettingsFlow {

    public func createSettingsFlow(options: OrySettingsFlowOptions) async throws -> OryFlow {
        try await settings.createSettingsFlow(sessionToken: requireSessionToken())
    }

    public func getSettingsFlow(id: String) async throws -> OryFlow {
        try await settings.getSettingsFlow(id: id, sessionToken: requireSessionToken())
    }

    public func submitSettingsFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OrySettingsResult> {
        let token = try await requireSessionToken()
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await settings.submitSettings(url: body.url, fields: body.fields, sessionToken: token)

        switch outcome {
        case let .completed(identity, verification):
            return .success(OrySettingsResult(identity: identity, verification: verification))
        case let .pending(flow):
            return .pending(flow)
        }
    }
}
