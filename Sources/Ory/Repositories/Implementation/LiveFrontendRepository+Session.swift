import Foundation

extension LiveFrontendRepository {

    func currentSession(sessionToken: String) async throws -> OrySession {
        let response = try await gateway.send(WhoamiRequest(sessionToken: sessionToken))
        return SessionMapper.flatMap(try gateway.decoded(response))
    }

    func revokeSession(sessionToken: String) async throws {
        let response = try await gateway.send(NativeLogoutRequest(sessionToken: sessionToken))
        switch response.status {
        case 200..<300:
            return
        case 403 where ErrorMapper.envelope(from: response.data).id == nil:
            // Native logout answers a token the server does not know with a 403 without an id.
            throw OryClientError.sessionExpired
        default:
            throw gateway.error(from: response)
        }
    }
}
