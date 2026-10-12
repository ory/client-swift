import Foundation
import OrySDK

extension LiveFrontendRepository {

    func createSettingsFlow(sessionToken: String) async throws -> OryFlow {
        let response = try await gateway.send(CreateSettingsFlowRequest(sessionToken: sessionToken))
        return FlowMapper.settings(try gateway.decoded(response))
    }

    func getSettingsFlow(id: String, sessionToken: String) async throws -> OryFlow {
        let response = try await gateway.send(GetSettingsFlowRequest(id: id, sessionToken: sessionToken))
        return FlowMapper.settings(try gateway.decoded(response))
    }

    func submitSettings(url submitURL: URL, fields: [String: String], sessionToken: String) async throws -> SettingsOutcome {
        let response = try await gateway.send(
            SubmitSettingsRequest(actionURL: submitURL, fields: fields, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.decode(OrySDKAPI.SettingsFlow.self)
            if let verification = settingsVerification(from: dto.continueWith) {
                return .completed(IdentityMapper.flatMap(dto.identity), verification: verification)
            }
            if dto.state == .success {
                return .completed(IdentityMapper.flatMap(dto.identity))
            }
            return .pending(FlowMapper.settings(dto))
        case 400:
            return .pending(FlowMapper.settings(try response.decode(OrySDKAPI.SettingsFlow.self)))
        default:
            // A change that needs a fresher session surfaces here as
            // ``OryClientError/reauthenticationRequired`` via the gateway's error mapping.
            throw gateway.error(from: response)
        }
    }

    private func settingsVerification(from continueWith: [OrySDKAPI.ContinueWith]?) -> OryVerificationHandle? {
        for item in continueWith ?? [] {
            if case let .typeContinueWithVerificationUi(verification) = item {
                return OryVerificationHandle(flowID: verification.flow.id, address: verification.flow.verifiableAddress)
            }
        }
        return nil
    }
}
