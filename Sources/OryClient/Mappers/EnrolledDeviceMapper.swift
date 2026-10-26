import Foundation

extension OryEnrolledDevice {

    /// Maps one server-listed key, marking it as this device when its id matches the one
    /// stored locally.
    init(_ record: DeviceKeyRecord, currentKeyID: String?) {
        self.init(
            clientKeyID: record.clientKeyID,
            name: record.deviceName,
            enrolledAt: record.createdAt,
            platform: Platform(rawValue: record.deviceType),
            userVerification: OryDeviceUserVerification(wireValue: record.userVerification),
            // Only "locked" is actionable for the app; any other state means the key is in
            // normal service as far as a device list is concerned.
            isLocked: record.state == "locked",
            isCurrentDevice: record.clientKeyID == currentKeyID
        )
    }
}

private extension OryDeviceUserVerification {
    /// A value this build does not know degrades to `.none`: it is the conservative reading —
    /// the app must not promise the user a verification step it cannot describe.
    init(wireValue: String) {
        self = OryDeviceUserVerification(rawValue: wireValue) ?? .none
    }
}
