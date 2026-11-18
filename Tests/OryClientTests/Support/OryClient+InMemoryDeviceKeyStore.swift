@testable import Ory
import OryTestDoubles

extension OryClient {
    /// Test convenience for suites that never enroll a device: the package's test bundle has no
    /// Keychain entitlement, so the device key lives in memory.
    convenience init(
        storage: OrySessionStorage,
        frontend: any ElementsConfigurationRepository & SessionRepository & LoginRepository & RegistrationRepository & VerificationRepository & RecoveryRepository & SettingsRepository,
        deviceAuthn: any DeviceAuthnRepository
    ) {
        self.init(storage: storage, frontend: frontend, deviceAuthn: deviceAuthn, deviceKeyStore: InMemoryDeviceKeyStore())
    }
}
