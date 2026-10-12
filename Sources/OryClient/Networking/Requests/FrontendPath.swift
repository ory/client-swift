/// Frontend API endpoint paths, relative to the project base URL. Defined once instead
/// of as string literals scattered across the request catalog.
enum FrontendPath {
    static let whoami = "/sessions/whoami"
    static let nativeLoginFlow = "/self-service/login/api"
    static let nativeRegistrationFlow = "/self-service/registration/api"
    static let nativeVerificationFlow = "/self-service/verification/api"
    static let verificationFlows = "/self-service/verification/flows"
    static let nativeRecoveryFlow = "/self-service/recovery/api"
    static let nativeSettingsFlow = "/self-service/settings/api"
    static let settingsFlows = "/self-service/settings/flows"
    static let nativeLogout = "/self-service/logout/api"
}
