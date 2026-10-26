import Foundation
import OrySDK

/// `GET /self-service/registration/api` — a native registration flow.
struct CreateRegistrationFlowRequest: FrontendRequest {
    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.nativeRegistrationFlow) }
    typealias Response = OrySDKAPI.RegistrationFlow
}

/// `GET /self-service/registration/flows?id=` — an existing registration flow by id, for example the
/// replacement the server names when a flow expired.
struct GetRegistrationFlowRequest: FrontendRequest {
    let id: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.registrationFlows, query: [URLQueryItem(name: "id", value: id)]) }
    typealias Response = OrySDKAPI.RegistrationFlow
}

/// `POST <action>` — submits a registration flow's form. A 2xx yields a successful
/// registration; a `400` re-renders the flow (decoded by the repository).
struct SubmitRegistrationRequest: FrontendRequest {
    let actionURL: URL
    let fields: [String: String]
    let sessionToken: String?

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { fields }
    var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
    typealias Response = OrySDKAPI.SuccessfulNativeRegistration
}
