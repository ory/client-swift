import Foundation
import OrySDK

/// `GET /sessions/whoami` — the session for a token.
struct WhoamiRequest: FrontendRequest {
    let sessionToken: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.whoami) }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.Session
}

/// `DELETE /self-service/logout/api` — native logout. The token travels in the body, not
/// the `X-Session-Token` header, so this request is unauthenticated.
struct NativeLogoutRequest: FrontendRequest {
    let sessionToken: String

    var method: HTTPMethod { .delete }
    var target: RequestTarget { .path(FrontendPath.nativeLogout) }
    var body: (any Encodable & Sendable)? { OrySDKAPI.PerformNativeLogoutBody(sessionToken: sessionToken) }
    typealias Response = OryEmptyResponse
}
