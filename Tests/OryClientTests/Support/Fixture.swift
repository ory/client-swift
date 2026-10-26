import Foundation
import Testing

enum Fixture {

    // MARK: - Named fixtures

    // Public Apple attestation from backend deviceauthn/testdata/ios_attestation.cbor.
    // OpenSSL x509 -pubkey | openssl pkey -pubin -outform DER | shasum -a 256.
    static let attestedClientKeyID = "02e4eebaa111878f108e34ae9162f9645bac36d3edeab5aa76ef36c0149fb841"
    static var deviceAttestation: Data { load("ios-attestation", extension: "cbor") }

    static var session: Data { load("session") }
    static var sessionUnknownAAL: Data { load("session-unknown-aal") }
    static var successfulLogin: Data { load("successful-login") }
    static var loginFlow: Data { load("login-flow") }
    static var loginFlowDeviceAuthn: Data { load("login-flow-deviceauthn") }
    static var settingsFlowDeviceAuthn: Data { load("settings-flow-deviceauthn") }
    static var settingsFlowDeviceAuthnUnknownContinueWith: Data { load("settings-flow-deviceauthn-unknown-continue-with") }
    static var settingsFlowDeviceList: Data { load("settings-flow-device-list") }
    static var loginFlowUnknownValues: Data { load("login-flow-unknown-values") }
    static var loginFlowUnknownNodeType: Data { load("login-flow-unknown-node-type") }
    static var successfulLoginUnknownContinueWith: Data { load("successful-login-unknown-continue-with") }
    static var successfulRegistrationUnknownContinueWith: Data { load("successful-registration-unknown-continue-with") }
    static var registrationFlow: Data { load("registration-flow") }
    static var successfulRegistration: Data { load("successful-registration") }
    static var successfulRegistrationNoSession: Data { load("successful-registration-no-session") }
    static var successfulRegistrationIdentityInSession: Data { load("successful-registration-identity-in-session") }
    static var successfulRegistrationNoIdentity: Data { load("successful-registration-no-identity") }
    static var successfulRegistrationVerification: Data { load("successful-registration-verification") }
    static var verificationFlow: Data { load("verification-flow") }
    static var verificationFlowVerified: Data { load("verification-flow-verified") }
    static var recoveryFlow: Data { load("recovery-flow") }
    static var recoveryPassedChallenge: Data { load("recovery-passed-challenge") }
    static var recoveryPassedChallengeUnknownContinueWith: Data { load("recovery-passed-challenge-unknown-continue-with") }
    static var settingsFlow: Data { load("settings-flow") }
    static var settingsFlowSuccess: Data { load("settings-flow-success") }
    static var settingsFlowValidationAfterSuccess: Data { load("settings-flow-validation-after-success") }
    static var settingsFlowVerification: Data { load("settings-flow-verification") }
    static var settingsPrivilegedError: Data { load("settings-privileged-error") }
    static var errorFlow: Data { load("error-flow") }
    static var errorGeneric: Data { load("error-generic") }
    static var errorFlowExpired: Data { load("error-flow-expired") }

    // MARK: - Loading

    static func load(_ name: String, extension fileExtension: String = "json") -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures") else {
            Issue.record("Missing fixture: Fixtures/\(name).\(fileExtension)")
            return Data()
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            Issue.record("Could not read fixture \(name).\(fileExtension): \(error)")
            return Data()
        }
    }
}
