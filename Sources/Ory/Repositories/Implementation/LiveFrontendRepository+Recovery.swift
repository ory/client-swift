import Foundation
import _OryGeneratedAPI

extension LiveFrontendRepository {

    func createRecoveryFlow() async throws -> OryFlow {
        let response = try await gateway.send(CreateRecoveryFlowRequest())
        return FlowMapper.recovery(try gateway.decoded(response))
    }

    func getRecoveryFlow(id: String) async throws -> OryFlow {
        let response = try await gateway.send(GetRecoveryFlowRequest(id: id))
        return FlowMapper.recovery(try gateway.decoded(response))
    }

    func submitRecovery(url submitURL: URL, fields: [String: String]) async throws -> RecoveryOutcome {
        let response = try await gateway.send(SubmitRecoveryRequest(actionURL: submitURL, fields: fields))

        // A submission the flow can no longer take, for example one repeated after the flow was
        // completed, returns an error that names a new recovery flow carrying the reason.
        if !(200..<300).contains(response.status), response.status != 410,
           let replacementID = ErrorMapper.envelope(from: response.data).continuation.recoveryFlowID {
            return .pending(try await getRecoveryFlow(id: replacementID))
        }

        switch response.status {
        case 200..<300, 400:
            // Both statuses return the flow; completion is signaled by its state.
            let dto = try response.decode(OrySDKAPI.RecoveryFlow.self)
            if dto.state == .passedChallenge {
                let continuation = ContinuationMapper.map(dto.continueWith)
                return .completed(token: continuation.sessionToken, settingsFlowID: continuation.settings?.flowID)
            }
            return .pending(FlowMapper.recovery(dto))
        default:
            throw gateway.error(from: response)
        }
    }
}
