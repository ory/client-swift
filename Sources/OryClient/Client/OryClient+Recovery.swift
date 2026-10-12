import Foundation

extension OryClient: OryRecoveryFlow {

    public func createRecoveryFlow() async throws -> OryFlow {
        try await recovery.createRecoveryFlow()
    }

    public func submitRecoveryFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRecoveryResult> {
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await recovery.submitRecovery(url: body.url, fields: body.fields)

        switch outcome {
        case let .completed(token, settingsFlowID):
            if let token {
                try await storeToken(token)
            }
            return .success(OryRecoveryResult(settings: settingsFlowID.map(OrySettingsHandle.init(flowID:))))

        case let .pending(flow):
            return .pending(flow)
        }
    }
}
