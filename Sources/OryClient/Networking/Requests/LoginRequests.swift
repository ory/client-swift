import Foundation
import OrySDK

/// `GET /self-service/login/api` — a native login flow. Also serves as the passwordless
/// first-factor device challenge (a fresh, unauthenticated login flow).
struct CreateLoginFlowRequest: FrontendRequest {
    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.nativeLoginFlow) }
    typealias Response = OrySDKAPI.LoginFlow
}

/// `POST <action>` — submits a login flow's form. A 2xx yields a successful login; a
/// `400` re-renders the flow (decoded by the repository).
struct SubmitLoginRequest: FrontendRequest {
    let actionURL: URL
    let fields: [String: String]
    let sessionToken: String?

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { fields }
    var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
    typealias Response = OrySDKAPI.SuccessfulNativeLogin
}
