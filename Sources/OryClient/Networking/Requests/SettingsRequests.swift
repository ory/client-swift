import Foundation
import OrySDK

/// `GET /self-service/settings/flows?id=` — an existing settings flow by id (for example
/// the one recovery surfaced to set a new password). Authenticated with the session token.
struct GetSettingsFlowRequest: FrontendRequest {
    let id: String
    let sessionToken: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.settingsFlows, query: [URLQueryItem(name: "id", value: id)]) }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.SettingsFlow
}

/// `POST <action>` — submits a settings flow's form (change password, update traits, manage
/// factors). Authenticated with the session token. Settings is state-driven: a `200`
/// returns the flow with `state == success`; a `400` re-renders it with validation errors.
struct SubmitSettingsRequest: FrontendRequest {
    let actionURL: URL
    let fields: [String: String]
    let sessionToken: String

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { fields }
    var authorization: RequestAuthorization { .sessionToken(sessionToken) }
    typealias Response = OrySDKAPI.SettingsFlow
}
