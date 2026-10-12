import Foundation
import OrySDK

extension LiveFrontendRepository {

    func createVerificationFlow() async throws -> OryFlow {
        let response = try await gateway.send(CreateVerificationFlowRequest())
        return FlowMapper.verification(try gateway.decoded(response))
    }

    func getVerificationFlow(id: String) async throws -> OryFlow {
        let response = try await gateway.send(GetVerificationFlowRequest(id: id))
        return FlowMapper.verification(try gateway.decoded(response))
    }

    func submitVerification(url submitURL: URL, fields: [String: String]) async throws -> VerificationOutcome {
        let response = try await gateway.send(SubmitVerificationRequest(actionURL: submitURL, fields: fields))

        switch response.status {
        case 200..<300, 400:
            // Both statuses return the flow; completion is signaled by its state.
            let dto = try response.decode(OrySDKAPI.VerificationFlow.self)
            if dto.state == .passedChallenge {
                return .completed
            }
            return .pending(FlowMapper.verification(dto))
        default:
            throw gateway.error(from: response)
        }
    }
}
