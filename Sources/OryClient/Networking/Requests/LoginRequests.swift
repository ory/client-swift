import Foundation
import OrySDK

/// `GET /self-service/login/api` — a native login flow. Also serves as the passwordless
/// first-factor device challenge (a fresh, unauthenticated login flow).
///
/// A re-authentication (`refresh`) or second-factor (`aal`) flow belongs to an existing
/// session, so it is created with that session's token.
struct CreateLoginFlowRequest: FrontendRequest {
    var refresh = false
    var aal: OryAuthenticatorAssuranceLevel?
    var sessionToken: String?

    var method: HTTPMethod { .get }
    var target: RequestTarget {
        var query: [URLQueryItem] = []
        if refresh {
            query.append(URLQueryItem(name: "refresh", value: "true"))
        }
        if let aal {
            query.append(URLQueryItem(name: "aal", value: aal.rawValue))
        }
        return .path(FrontendPath.nativeLoginFlow, query: query)
    }
    var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
    typealias Response = OrySDKAPI.LoginFlow
}

/// `GET /self-service/login/flows?id=` — an existing login flow by id, for example the
/// replacement the server names when a flow expired.
struct GetLoginFlowRequest: FrontendRequest {
    let id: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.loginFlows, query: [URLQueryItem(name: "id", value: id)]) }
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
