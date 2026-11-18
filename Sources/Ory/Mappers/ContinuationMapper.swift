import Foundation
import _OryGeneratedAPI

/// The next steps a native flow response names in its `continue_with` items.
struct FlowContinuation: Sendable, Equatable {
    var sessionToken: String?
    var verification: OryVerificationHandle?
    var settings: OrySettingsHandle?
    var recoveryFlowID: String?
}

enum ContinuationMapper {

    /// Reads the first item of each kind. `redirect_browser_to` is sent to browser flows only,
    /// device PIN entry is read by device authentication, and items this build does not know
    /// are skipped.
    static func map(_ items: [OrySDKAPI.ContinueWith]?) -> FlowContinuation {
        var continuation = FlowContinuation()
        for item in items ?? [] {
            switch item {
            case let .typeContinueWithSetOrySessionToken(token):
                continuation.sessionToken = continuation.sessionToken ?? token.orySessionToken
            case let .typeContinueWithVerificationUi(verification):
                continuation.verification = continuation.verification ?? OryVerificationHandle(
                    flowID: verification.flow.id,
                    address: verification.flow.verifiableAddress
                )
            case let .typeContinueWithSettingsUi(settings):
                continuation.settings = continuation.settings ?? OrySettingsHandle(flowID: settings.flow.id)
            case let .typeContinueWithRecoveryUi(recovery):
                continuation.recoveryFlowID = continuation.recoveryFlowID ?? recovery.flow.id
            case .typeContinueWithRedirectBrowserTo, .typeContinueWithDeviceAuthnPinEntryUi, .unknownDefaultOpenApi:
                continue
            }
        }
        return continuation
    }
}
