import Foundation

/// How the holder of a device key is verified at use time, mirroring the backend's
/// `user_verification` on the `deviceauthn` credential.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryDeviceUserVerification: String, Sendable, Codable {

    /// Possession only. A second factor for AAL2 step-up, never a sole first factor.
    case none

    /// PIN-protected. Passwordless 1FA with the user's PIN (`pin_proof`), and step-up.
    case pin

    /// Biometric-gated (Face ID / Touch ID / Optic ID). Passwordless 1FA and step-up; the
    /// client gates signing behind biometrics, which the iOS backend trusts on enrollment.
    case platform
}

/// A device key enrolled on this device: the server's `client_key_id` (sent when signing
/// in and removing) paired with the authenticator's local handle (used to produce the
/// signature — App Attest's key id on device, or the relaxed authenticator's handle).
///
/// `userVerification` records how the key authenticates its holder, matching the mode it was
/// enrolled with. `pinSecret` is present only for a `.pin` key. Only a `.pin` or `.platform`
/// key can perform passwordless 1FA login; a `.none` key is step-up only.
///
/// Treat the value as opaque in a custom ``OryDeviceKeyStore``: persist and return it
/// unchanged (it is `Codable`), and never alter its fields — ``OryClient`` owns their
/// meaning.
public struct OryStoredDeviceKey: Sendable, Codable, Equatable {

    /// The layout this build writes and can read back.
    static let currentSchemaVersion = 1

    /// The layout of this record. A store that reads a version it does not know treats the
    /// record as absent, so an app downgrade — or a future change to what is persisted —
    /// leads to re-enrollment instead of an unreadable state.
    ///
    /// Records written before versioning existed decode as version 1, which is what they are.
    public private(set) var schemaVersion: Int = OryStoredDeviceKey.currentSchemaVersion

    /// The server-side credential identifier, sent when signing in and removing the key.
    public let clientKeyID: String

    /// The authenticator's local key handle used to produce signatures.
    public let localKeyID: String

    /// The PIN-protected secret, present only for a ``OryDeviceUserVerification/pin`` key.
    /// Opaque — its contents are managed by ``OryClient``.
    public internal(set) var pinSecret: OryProtectedPINSecret?

    /// How the key authenticates its holder.
    public internal(set) var userVerification: OryDeviceUserVerification

    /// Creates a stored key. Provided for tests; ``OryClient`` creates these during
    /// enrollment.
    public init(
        clientKeyID: String,
        localKeyID: String,
        pinSecret: OryProtectedPINSecret? = nil,
        userVerification: OryDeviceUserVerification
    ) {
        self.clientKeyID = clientKeyID
        self.localKeyID = localKeyID
        self.pinSecret = pinSecret
        self.userVerification = userVerification
    }

    // Written by hand rather than synthesized: Swift's generated decoder ignores a property's
    // default value and fails on a missing key, which would make every record enrolled before
    // versioning existed unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        clientKeyID = try container.decode(String.self, forKey: .clientKeyID)
        localKeyID = try container.decode(String.self, forKey: .localKeyID)
        pinSecret = try container.decodeIfPresent(OryProtectedPINSecret.self, forKey: .pinSecret)
        userVerification = try container.decode(OryDeviceUserVerification.self, forKey: .userVerification)
    }
}

/// Persists the device key enrolled on this device.
///
/// Kept separate from ``OrySessionStorage``: the key is tied to the device and its server-side
/// credential, so it must outlive a single session (it survives sign-out, unlike the session
/// token). ``OryClient`` reads and writes it exclusively through this protocol.
///
/// The default implementation is ``OryKeychainDeviceKeyStore``. Pass your own via
/// ``OryClientConfiguration/deviceKeyStore`` when you need different behavior — for
/// example a Keychain access group shared with an app extension, or an in-memory store
/// in tests (`InMemoryDeviceKeyStore` from `OryClientTestDoubles`):
///
/// ```swift
/// let config = OryClientConfiguration(
///     projectURL: projectURL,
///     deviceKeyStore: OryKeychainDeviceKeyStore(accessGroup: "TEAMID.com.acme.shared")
/// )
/// ```
public protocol OryDeviceKeyStore: Sendable {

    /// A stable identifier for the storage slot used to coordinate device operations
    /// across client instances in this process.
    ///
    /// Every store accessing the same slot must return the same value, including wrappers
    /// around another store. Forward the wrapped store's scope when decorating it. Keep
    /// the value unchanged for the lifetime of the store and independent of its current key.
    /// Stores for distinct slots should use distinct values so they can operate concurrently.
    ///
    /// The default groups custom stores into one shared scope. Override it to separate
    /// independent slots; use a persistent per-slot identifier for shared storage or one
    /// UUID per in-memory store instance. Scope values are identifiers, never credentials.
    ///
    /// Coordination covers operations performed through `OryClient` in this process.
    /// Direct writes to the store and writes from other processes must not run concurrently
    /// with those operations; the scope does not make storage reads and writes atomic.
    var deviceOperationScope: String { get }

    /// Returns the enrolled key, or `nil` when this device has no enrolled key.
    func enrolledKey() async throws -> OryStoredDeviceKey?

    /// Stores the enrolled key, replacing any previously stored value.
    func store(_ key: OryStoredDeviceKey) async throws

    /// Removes the stored key, for example after removing the device credential.
    func clear() async throws
}

public extension OryDeviceKeyStore {
    /// Groups custom stores that do not provide their own slot identifier into one scope.
    var deviceOperationScope: String { "ory.custom-device-key-store" }
}
