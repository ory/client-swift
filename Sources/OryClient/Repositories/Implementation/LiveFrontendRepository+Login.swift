import Foundation
import OrySDK

extension LiveFrontendRepository {

    func createLoginFlow() async throws -> OryFlow {
        let response = try await gateway.send(CreateLoginFlowRequest())
        return FlowMapper.login(try gateway.decoded(response))
    }

    func submitLogin(url submitURL: URL, fields: [String: String], sessionToken: String?) async throws -> LoginSubmissionOutcome {
        let response = try await gateway.send(
            SubmitLoginRequest(actionURL: submitURL, fields: fields, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return .success(session: SessionMapper.flatMap(dto.session), token: dto.sessionToken)
        case 400:
            let dto = try response.decode(OrySDKAPI.LoginFlow.self)
            return .pending(FlowMapper.login(dto))
        default:
            throw gateway.error(from: response)
        }
    }
}
