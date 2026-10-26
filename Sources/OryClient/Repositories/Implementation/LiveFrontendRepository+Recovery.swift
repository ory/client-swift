import Foundation
import OrySDK

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

        switch response.status {
        case 200..<300, 400:
            // Both statuses return the flow; completion is signaled by its state.
            let dto = try response.decode(OrySDKAPI.RecoveryFlow.self)
            if dto.state == .passedChallenge {
                return .completed(
                    token: sessionToken(from: dto.continueWith),
                    settingsFlowID: settingsFlowID(from: dto.continueWith)
                )
            }
            return .pending(FlowMapper.recovery(dto))
        default:
            throw gateway.error(from: response)
        }
    }

    /// The privileged session token the server issues on successful recovery, delivered as
    /// a `set_ory_session_token` continue-with item on native flows.
    private func sessionToken(from continueWith: [OrySDKAPI.ContinueWith]?) -> String? {
        for item in continueWith ?? [] {
            if case let .typeContinueWithSetOrySessionToken(token) = item {
                return token.orySessionToken
            }
        }
        return nil
    }

    /// The settings flow the server directs the user to after recovery, to set a new
    /// password, delivered as a `settings_ui` continue-with item.
    private func settingsFlowID(from continueWith: [OrySDKAPI.ContinueWith]?) -> String? {
        for item in continueWith ?? [] {
            if case let .typeContinueWithSettingsUi(settings) = item {
                return settings.flow.id
            }
        }
        return nil
    }
}
