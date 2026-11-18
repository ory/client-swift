#if canImport(LocalAuthentication)
import LocalAuthentication
#endif
import Foundation
import Security

/// The kind of biometric hardware a device offers for device authentication.
///
/// Use it to label your sign-in UI correctly — for example "Sign in with Face ID" versus
/// "Sign in with Touch ID" — via ``OryClientProtocol/biometryType``.
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryBiometryType: Sendable, Equatable {

    /// No biometric hardware is enrolled or usable on this device.
    case none

    /// Face ID.
    case faceID

    /// Touch ID.
    case touchID

    /// Optic ID (Apple Vision Pro).
    case opticID
}

/// The seam over the local biometric check (Face ID / Touch ID / Optic ID) that gates every
/// signature with a biometric device key.
///
/// On iOS an App Attest key cannot itself be gated behind biometrics, and the Ory backend
/// **trusts the client's `platform` user-verification declaration** because it cannot prove
/// the gating remotely. ``OryClient`` therefore enforces the gate here: it calls
/// ``enroll(keyID:reason:)`` while enrolling a biometric (`platform`) key and
/// ``evaluate(keyID:reason:)`` immediately before every signature with it, so a stolen device
/// cannot enroll or sign in without the enrolled user. Honour that contract in any custom
/// implementation — a no-op `evaluate` silently downgrades the security of every biometric
/// sign-in.
///
/// The production implementation is ``OryLocalAuthenticationBiometricAuthenticator`` (used by
/// default). Conform your own type only to unit-test biometric flows without a prompt; inject
/// it via ``OryClientConfiguration/biometricAuthenticator``.
public protocol OryBiometricAuthenticator: Sendable {

    /// The biometric hardware available on this device, or ``OryBiometryType/none`` when
    /// biometrics cannot be used (no hardware, none enrolled, or locked out).
    var biometryType: OryBiometryType { get }

    /// Whether the device can perform a biometric check right now — hardware present,
    /// biometrics enrolled, and not locked out. Guard biometric enrollment and sign-in with
    /// this so you never prompt where it cannot succeed.
    var isAvailable: Bool { get }

    /// Binds a new biometric device key to the biometrics enrolled on this device right now,
    /// prompting the user once to confirm them.
    ///
    /// ``OryClient`` calls this while enrolling a biometric key, before the key is registered
    /// with Ory. From then on ``evaluate(keyID:reason:)`` for the same `keyID` must succeed only
    /// for exactly those biometrics.
    ///
    /// - Parameters:
    ///   - keyID: The device key's local handle, ``OryStoredDeviceKey/localKeyID``.
    ///   - reason: The localized message shown in the system prompt.
    /// - Throws: ``OryClientError/deviceAuthenticationCancelled`` when the user cancels or
    ///   falls back, ``OryClientError/deviceAuthenticationBiometricsUnavailable`` when
    ///   biometrics cannot be evaluated, or ``OryClientError/deviceAuthenticationFailed(underlying:)``
    ///   on any other failure.
    func enroll(keyID: String, reason: String) async throws

    /// Prompts the user for biometric verification against the biometrics bound by
    /// ``enroll(keyID:reason:)``, throwing if it does not succeed.
    ///
    /// - Parameters:
    ///   - keyID: The device key's local handle, ``OryStoredDeviceKey/localKeyID``.
    ///   - reason: The localized message shown in the system prompt, explaining why
    ///     verification is needed.
    /// - Throws: ``OryClientError/deviceAuthenticationBiometricsChanged`` when the device's
    ///   biometrics changed since `keyID` was enrolled (a face or fingerprint was added or
    ///   removed) or the binding is missing, ``OryClientError/deviceAuthenticationCancelled``
    ///   when the user cancels or falls back, ``OryClientError/deviceAuthenticationBiometricsUnavailable``
    ///   when biometrics cannot be evaluated, or ``OryClientError/deviceAuthenticationFailed(underlying:)``
    ///   on any other failure.
    func evaluate(keyID: String, reason: String) async throws

    /// Removes the binding ``enroll(keyID:reason:)`` created for `keyID`. Best effort: a
    /// missing binding is ignored.
    ///
    /// - Parameter keyID: The device key's local handle, ``OryStoredDeviceKey/localKeyID``.
    func removeEnrollment(keyID: String) async
}

#if canImport(LocalAuthentication)

/// The production ``OryBiometricAuthenticator``, backed by `LocalAuthentication` and a
/// Secure Enclave key bound to the device's current biometrics.
///
/// Enrollment creates a Secure Enclave key whose access control is `.biometryCurrentSet`, and
/// every check signs with it. The Secure Enclave releases that key only for the Face ID /
/// Touch ID / Optic ID enrolled when the key was created — a device passcode never does — and
/// invalidates it when a face or fingerprint is added or removed, or when the passcode is
/// removed. Someone who learns the device passcode therefore cannot enroll their own face and
/// sign in as the user: the check throws ``OryClientError/deviceAuthenticationBiometricsChanged``
/// instead. This is the default, so you rarely construct it directly.
///
/// Your app's `Info.plist` must contain an `NSFaceIDUsageDescription` string, or the Face ID
/// prompt fails.
public struct OryLocalAuthenticationBiometricAuthenticator: OryBiometricAuthenticator {

    /// Creates the LocalAuthentication biometric authenticator.
    public init() {}

    public var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public var biometryType: OryBiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            #if !os(macOS)
            if #available(iOS 17.0, *), context.biometryType == .opticID {
                return .opticID
            }
            #endif
            return .none
        }
    }

    public func enroll(keyID: String, reason: String) async throws {
        let tag = Self.tag(for: keyID)
        Self.deleteBinding(tag: tag)
        try Self.createKey(tag: tag)
        do {
            let context = LAContext()
            try await Self.authenticate(context, reason: reason)
            guard let biometricSet = context.evaluatedPolicyDomainState else {
                throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.biometricSetUnavailable)
            }
            try Self.sign(tag: tag, context: context)
            try Self.storeEnrolledBiometricSet(biometricSet, tag: tag)
        } catch OryClientError.deviceAuthenticationBiometricsChanged {
            Self.deleteBinding(tag: tag)
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.newKeyUnusable)
        } catch {
            Self.deleteBinding(tag: tag)
            throw error
        }
    }

    public func evaluate(keyID: String, reason: String) async throws {
        let tag = Self.tag(for: keyID)
        // Checked before prompting, so a binding that is already gone fails without a prompt.
        guard try Self.copyKey(tag: tag, context: nil) != nil,
              let enrolledSet = try Self.enrolledBiometricSet(tag: tag)
        else {
            throw OryClientError.deviceAuthenticationBiometricsChanged
        }

        let context = LAContext()
        try await Self.authenticate(context, reason: reason)
        try Self.verifyBiometricSet(enrolled: enrolledSet, current: context.evaluatedPolicyDomainState)
        try Self.sign(tag: tag, context: context)
    }

    public func removeEnrollment(keyID: String) async {
        Self.deleteBinding(tag: Self.tag(for: keyID))
    }

    /// Only the domain state identifies a changed biometric set; a refused signature has many causes.
    static func verifyBiometricSet(enrolled: Data, current: Data?) throws {
        guard let current else {
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.biometricSetUnavailable)
        }
        guard current == enrolled else {
            throw OryClientError.deviceAuthenticationBiometricsChanged
        }
    }

    // MARK: - Secure Enclave binding

    private static func tag(for keyID: String) -> String {
        "com.ory.client.deviceauthn.biometric-binding.\(keyID)"
    }

    private static func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw OryClientError.deviceAuthenticationFailed(
                underlying: UnderlyingError(error!.takeRetainedValue() as Error)
            )
        }
        return access
    }

    private static func createKey(tag: String) throws {
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
                kSecAttrAccessControl as String: try accessControl(),
            ] as [String: Any],
        ]
        // The Simulator has no Secure Enclave; it gets a software key with the same access control.
        #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            throw OryClientError.deviceAuthenticationFailed(
                underlying: UnderlyingError(error!.takeRetainedValue() as Error)
            )
        }
    }

    /// Signs a throwaway nonce with the bound key through the context that already passed the
    /// prompt. The signature itself is discarded: the Secure Enclave refusing to sign is the gate.
    private static func sign(tag: String, context: LAContext) throws {
        guard let key = try copyKey(tag: tag, context: context) else {
            throw OryClientError.deviceAuthenticationBiometricsChanged
        }
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else {
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.keychain(status: status))
        }
        var error: Unmanaged<CFError>?
        guard SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, nonce as CFData, &error) != nil else {
            throw OryClientError.deviceAuthenticationFailed(
                underlying: UnderlyingError(error!.takeRetainedValue() as Error)
            )
        }
    }

    /// Prompts for biometrics on `context`, which the signature that follows reuses instead of
    /// prompting a second time.
    private static func authenticate(_ context: LAContext, reason: String) async throws {
        do {
            let succeeded = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard succeeded else {
                throw OryClientError.deviceAuthenticationCancelled
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                throw OryClientError.deviceAuthenticationCancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                throw OryClientError.deviceAuthenticationBiometricsUnavailable
            default:
                throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
            }
        } catch let error as OryClientError {
            throw error
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
        }
    }

    private static func copyKey(tag: String, context: LAContext?) throws -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecReturnRef as String: true,
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else {
                throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.unexpectedItem)
            }
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.keychain(status: status))
        }
    }

    private static func storeEnrolledBiometricSet(_ biometricSet: Data, tag: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecValueData as String: biometricSet,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.keychain(status: status))
        }
    }

    private static func enrolledBiometricSet(tag: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.unexpectedItem)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw OryClientError.deviceAuthenticationFailed(underlying: BiometricBindingError.keychain(status: status))
        }
    }

    private static func deleteBinding(tag: String) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
        ]
        let biometricSet: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
        ]
        SecItemDelete(key as CFDictionary)
        SecItemDelete(biometricSet as CFDictionary)
    }
}

private enum BiometricBindingError: Error, Sendable, LocalizedError {
    case newKeyUnusable
    case biometricSetUnavailable
    case unexpectedItem
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .newKeyUnusable:
            return "The new biometric key could not be used right after it was created."
        case .biometricSetUnavailable:
            return "The device did not report its enrolled biometrics."
        case .unexpectedItem:
            return "The biometric key stored in the Keychain has an unexpected type."
        case let .keychain(status):
            return "Accessing the biometric key failed (status \(status))."
        }
    }
}

#endif
