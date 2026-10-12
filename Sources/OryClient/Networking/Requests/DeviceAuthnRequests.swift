import Foundation
import OrySDK

/// `GET /self-service/settings/api` — a native settings flow. The device-authn flows read
/// its nonce, key ids, and submit URL, and post enrollment/removal/PIN updates back to it.
struct CreateSettingsFlowRequest: FrontendRequest {
    let sessionToken: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.nativeSettingsFlow) }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.SettingsFlow
}

/// `GET /self-service/login/api?refresh=false&aal=aal2` — an AAL2 native login flow, whose
/// device-authn challenge steps an existing session up to AAL2.
struct CreateAAL2LoginChallengeRequest: FrontendRequest {
    let sessionToken: String

    var method: HTTPMethod { .get }
    var target: RequestTarget {
        .path(FrontendPath.nativeLoginFlow, query: [
            URLQueryItem(name: "refresh", value: "false"),
            URLQueryItem(name: "aal", value: "aal2"),
        ])
    }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.LoginFlow
}

/// `POST <action>` — posts a device-authn update (register / remove / PIN enroll / rotate)
/// to a settings flow.
struct SubmitSettingsDeviceAuthnRequest: FrontendRequest {
    let actionURL: URL
    let update: OrySDKAPI.UpdateSettingsFlowWithDeviceAuthnMethod
    let sessionToken: String

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { update }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.SettingsFlow
}

/// `POST <action>` — submits a signed device-authn challenge to a login flow, for both
/// AAL2 step-up (with a session token) and passwordless first-factor login (without one).
struct SubmitDeviceLoginRequest: FrontendRequest {
    let actionURL: URL
    let update: OrySDKAPI.UpdateLoginFlowWithDeviceAuthnMethod
    let sessionToken: String?

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { update }
    var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
    typealias Response = OrySDKAPI.SuccessfulNativeLogin
}
