import Foundation
import OrySDK

/// `GET /self-service/recovery/api` — a native recovery flow.
struct CreateRecoveryFlowRequest: FrontendRequest {
    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.nativeRecoveryFlow) }
    typealias Response = OrySDKAPI.RecoveryFlow
}

/// `POST <action>` — submits a recovery flow's form. Recovery is state-driven: the server
/// returns the flow at each step (`choose_method` → `sent_email` → `passed_challenge`),
/// so both `200` and `400` return the flow and completion is read from its state.
struct SubmitRecoveryRequest: FrontendRequest {
    let actionURL: URL
    let fields: [String: String]

    var method: HTTPMethod { .post }
    var target: RequestTarget { .url(actionURL) }
    var body: (any Encodable & Sendable)? { fields }
    typealias Response = OrySDKAPI.RecoveryFlow
}
