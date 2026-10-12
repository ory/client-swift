#if canImport(LocalAuthentication)
import Foundation
import Testing
@testable import OryClient

@Suite("OryLocalAuthenticationBiometricAuthenticator.verifyBiometricSet")
struct BiometricBindingTests {

    private let enrolled = Data([0x01, 0x02, 0x03])

    @Test("accepts the biometric set captured at enrollment")
    func unchangedSet() throws {
        // Given the device reports the same biometric set as at enrollment.
        let current = enrolled

        // When / Then the check passes.
        try OryLocalAuthenticationBiometricAuthenticator.verifyBiometricSet(enrolled: enrolled, current: current)
    }

    @Test("reports changed biometrics when the device's biometric set differs")
    func changedSet() {
        // Given a face or fingerprint was added or removed since enrollment.
        let current = Data([0x09, 0x09, 0x09])

        // When the set is checked.
        let error = #expect(throws: OryClientError.self) {
            try OryLocalAuthenticationBiometricAuthenticator.verifyBiometricSet(enrolled: enrolled, current: current)
        }

        // Then the change is reported.
        #expect(error?.isDeviceAuthenticationBiometricsChanged == true)
    }

    @Test("reports a generic failure, not changed biometrics, when the device reports no biometric set")
    func missingSet() {
        // Given the device does not report its biometric set.
        let current: Data? = nil

        // When the set is checked.
        let error = #expect(throws: OryClientError.self) {
            try OryLocalAuthenticationBiometricAuthenticator.verifyBiometricSet(enrolled: enrolled, current: current)
        }

        // Then it is a generic failure, so the integrator does not forget the device.
        #expect(error?.isDeviceAuthenticationFailed == true)
    }
}
#endif
