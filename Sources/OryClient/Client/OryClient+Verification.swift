import Foundation

extension OryClient: OryVerificationFlow {

    public func createVerificationFlow() async throws -> OryFlow {
        try await verification.createVerificationFlow()
    }

    public func getVerificationFlow(id: String) async throws -> OryFlow {
        try await verification.getVerificationFlow(id: id)
    }

    public func submitVerificationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryVerificationResult> {
        let body = flow.makeBody(values: values, pressing: action)
        let outcome = try await verification.submitVerification(url: body.url, fields: body.fields)

        switch outcome {
        case .completed:
            return .success(OryVerificationResult())
        case let .pending(flow):
            return .pending(flow)
        }
    }
}
