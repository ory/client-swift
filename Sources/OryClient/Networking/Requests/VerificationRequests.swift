import Foundation
import OrySDK

/// `GET /self-service/verification/api` — a native verification flow.
struct CreateVerificationFlowRequest: FrontendRequest {
    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.nativeVerificationFlow) }
    typealias Response = OrySDKAPI.VerificationFlow
}

/// `GET /self-service/verification/flows?id=` — an existing verification flow by id (for
/// example the one a registration surfaced).
struct GetVerificationFlowRequest: FrontendRequest {
    let id: String

    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.verificationFlows, query: [URLQueryItem(name: "id", value: id)]) }
    typealias Response = OrySDKAPI.VerificationFlow
}

/// `POST <action>` — submits a verification flow's form. Verification is state-driven:
/// both `200` and `400` return the flow, and completion is read from its state.
struct SubmitVerificationRequest: FrontendRequest {
    let actionURL: URL
    let fields: [String: String]

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { fields }
    typealias Response = OrySDKAPI.VerificationFlow
}
