@testable import OryClient

extension OryClientError {
    var isNotAuthenticated: Bool { if case .notAuthenticated = self { true } else { false } }
    var isSessionExpired: Bool { if case .sessionExpired = self { true } else { false } }
    var serverStatus: Int? { if case let .server(status, _, _) = self { status } else { nil } }
    var isDeviceAuthenticationUnavailable: Bool { if case .deviceAuthenticationUnavailable = self { true } else { false } }
    var isDeviceAuthenticationNotEnrolled: Bool { if case .deviceAuthenticationNotEnrolled = self { true } else { false } }
    var isDeviceAuthenticationInvalidPIN: Bool { if case .deviceAuthenticationInvalidPIN = self { true } else { false } }
    var isDeviceAuthenticationPINRequired: Bool { if case .deviceAuthenticationPINRequired = self { true } else { false } }
    var isDeviceAuthenticationBiometricsUnavailable: Bool { if case .deviceAuthenticationBiometricsUnavailable = self { true } else { false } }
    var isDeviceAuthenticationBiometricsChanged: Bool { if case .deviceAuthenticationBiometricsChanged = self { true } else { false } }
    var isDeviceAuthenticationFailed: Bool { if case .deviceAuthenticationFailed = self { true } else { false } }
    var isDeviceAuthenticationCancelled: Bool { if case .deviceAuthenticationCancelled = self { true } else { false } }
    var isSecondFactorRequired: Bool { if case .secondFactorRequired = self { true } else { false } }
    var isReauthenticationRequired: Bool { if case .reauthenticationRequired = self { true } else { false } }
}
