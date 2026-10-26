import Foundation

/// A device enrolled for device authentication on the signed-in identity.
///
/// Returned by ``OryDeviceManagement/enrolledDevices()``. Use it to build a "your devices"
/// screen, and pass one back to ``OryDeviceManagement/removeDevice(_:)`` to revoke it — for
/// example when a user reports a phone lost.
public struct OryEnrolledDevice: Sendable, Hashable, Identifiable {

    /// The platform the device was enrolled on.
    ///
    /// A wrapper around the platform name Ory sends rather than an enum, because Ory adds
    /// platforms over time. Compare against the constants, and keep a `default:` arm when you
    /// `switch` over it — the compiler requires one:
    ///
    /// ```swift
    /// switch device.platform {
    /// case .iOS:
    ///     icon = Image(systemName: "iphone")
    /// case .android:
    ///     icon = Image(systemName: "candybarphone")
    /// default:
    ///     icon = Image(systemName: "questionmark.square")
    /// }
    /// ```
    public struct Platform: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

        /// The platform name as Ory sends it, for example `iOS`.
        public let rawValue: String

        /// Creates a platform from the name Ory sends.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String { rawValue }

        /// An iPhone or iPad.
        public static let iOS = Platform(rawValue: "iOS")

        /// An Android device.
        public static let android = Platform(rawValue: "Android")
    }

    /// The key's stable identifier, unique for this identity.
    public let clientKeyID: String

    /// Stable identity for SwiftUI lists and diffing.
    public var id: String { clientKeyID }

    /// The name submitted at enrollment, for example the device name the user sees in
    /// iOS Settings. Chosen by whoever enrolled it, so treat it as untrusted display text.
    public let name: String

    /// When the device was enrolled.
    public let enrolledAt: Date

    /// The platform the device was enrolled on.
    public let platform: Platform

    /// How this device verifies its holder: a PIN, the platform's biometrics, or nothing
    /// (possession only).
    public let userVerification: OryDeviceUserVerification

    /// Whether the device's key is locked after too many wrong PIN attempts.
    ///
    /// A locked device cannot sign in until its PIN is reset from that device
    /// (``OryDeviceManagement/resetDevicePIN(newPin:)``). It also stops counting as a second
    /// factor, which is what lets the user recover.
    public let isLocked: Bool

    /// Whether this entry is the device the app is running on.
    ///
    /// Use it to label the current device and to warn before revoking it — removing it signs
    /// this device out of device authentication and requires enrolling again.
    public let isCurrentDevice: Bool

    /// Creates an enrolled device. Provided for tests and previews; ``OryClient`` builds these
    /// from the server's response.
    public init(
        clientKeyID: String,
        name: String,
        enrolledAt: Date,
        platform: Platform,
        userVerification: OryDeviceUserVerification,
        isLocked: Bool,
        isCurrentDevice: Bool
    ) {
        self.clientKeyID = clientKeyID
        self.name = name
        self.enrolledAt = enrolledAt
        self.platform = platform
        self.userVerification = userVerification
        self.isLocked = isLocked
        self.isCurrentDevice = isCurrentDevice
    }
}
