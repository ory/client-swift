import Foundation
import OrySDK

extension LiveFrontendRepository {

    func createRegistrationFlow() async throws -> OryFlow {
        let response = try await gateway.send(CreateRegistrationFlowRequest())
        return FlowMapper.registration(try gateway.decoded(response))
    }

    func getRegistrationFlow(id: String) async throws -> OryFlow {
        let response = try await gateway.send(GetRegistrationFlowRequest(id: id))
        return FlowMapper.registration(try gateway.decoded(response))
    }

    func submitRegistration(url submitURL: URL, fields: [String: String], sessionToken: String?) async throws -> RegistrationOutcome {
        let response = try await gateway.send(
            SubmitRegistrationRequest(actionURL: submitURL, fields: fields, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            guard let identity = dto.identity ?? dto.session?.identity else {
                throw OryClientError.unexpectedResponse(underlying: RegistrationResponseError.identityMissing)
            }
            return .success(
                identity: IdentityMapper.flatMap(identity),
                session: dto.session.map { SessionMapper.flatMap($0) },
                token: dto.sessionToken,
                verification: verificationHandle(from: dto.continueWith)
            )
        case 400:
            let dto = try response.decode(OrySDKAPI.RegistrationFlow.self)
            return .pending(FlowMapper.registration(dto))
        default:
            throw gateway.error(from: response)
        }
    }

    /// Extracts the verification the server wants the user to complete next, if any.
    private func verificationHandle(from continueWith: [OrySDKAPI.ContinueWith]?) -> OryVerificationHandle? {
        for item in continueWith ?? [] {
            if case let .typeContinueWithVerificationUi(verification) = item {
                return OryVerificationHandle(flowID: verification.flow.id, address: verification.flow.verifiableAddress)
            }
        }
        return nil
    }
}

private enum RegistrationResponseError: Error, Sendable, LocalizedError {
    case identityMissing

    var errorDescription: String? {
        "The registration response did not include the created identity."
    }
}
