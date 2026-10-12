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
        default:
            throw gateway.error(from: response)
        }
    }
}
