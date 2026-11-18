import Foundation
import _OryGeneratedAPI

/// `GET /elements/configuration` — the project's Ory Elements configuration. Public, so it
/// sends no session token.
struct ElementsConfigurationRequest: FrontendRequest {
    var method: HTTPMethod { .get }
    var target: RequestTarget { .path(FrontendPath.elementsConfiguration) }
    typealias Response = OrySDKAPI.ElementsConfiguration
}
