import CommonCrypto
import CryptoKit
import Foundation
import Security
import Sodium

/// The PIN material stored for a PIN-protected device key, following the recipe in the
/// published device-authn client guide: the `pin_secret` encrypted with AES-CTR under an
/// Argon2id PIN-derived key, then wrapped with ECIES under a Secure Enclave key.
///
/// The inner AES-CTR layer is **deliberately unauthenticated**: a wrong PIN must yield
/// plausible garbage, never a locally detectable failure, so the Kratos server stays the
/// only PIN oracle and every wrong guess spends one of the key's `pin_max_attempts`.
public struct OryProtectedPINSecret: Sendable, Codable, Equatable {
    /// Format version of this recipe.
    let version: Int
    /// Argon2id salt — fresh on every seal.
    let salt: Data
    /// AES-CTR IV — fresh on every seal. Reusing either the salt or the IV across seals
    /// would leak the secret via CTR keystream reuse.
    let iv: Data
    /// Argon2id parameters chosen at seal time; unsealing must re-derive with the same values.
    let opsLimit: Int
    let memLimit: Int
    /// Keychain tag of the Secure Enclave key that wraps `sealed` — a fresh key per seal,
    /// created by ``DevicePINVault/protect(pinSecret:pin:)`` and deleted when the material
    /// it protects is replaced or forgotten.
    let sealingKeyTag: String
    /// `ECIES(SE key, AES-CTR(pinKey, pin_secret))`.
    let sealed: Data
}

/// An ephemeral X25519 transport key pair the device generates per PIN enrollment. The
/// public key is sent to the server, which HPKE-seals the `pin_secret` to it; the private
/// key opens it and is then discarded.
struct TransportKey: Sendable {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    var publicKey: Data { privateKey.publicKey.rawRepresentation }
}

/// Device-authn PIN cryptography, per the published client guide:
///
/// - HPKE (DHKEM(X25519, HKDF-SHA256) / HKDF-SHA256 / AES-128-GCM) to open the
///   server-sealed `pin_secret`.
/// - Argon2id (libsodium) + unauthenticated AES-CTR + a Secure Enclave ECIES wrap to
///   protect the `pin_secret` at rest under the user's PIN (see ``OryProtectedPINSecret``).
/// - HMAC-SHA256 to compute the `pin_proof` submitted at login.
///
/// The wire-facing constants mirror the backend (`deviceauthnprotocol/{hpke,pin}.go`)
/// exactly and must not change independently. The at-rest constants are device-local.
struct DevicePINVault: Sendable {

    private static let hpkeInfo = Data("ory/deviceauthn/pin-secret/v1".utf8)
    private static let pinProofDomain = Data("ory/deviceauthn/pin-proof/v1".utf8)

    /// Prefix of the per-seal Keychain tags under which sealing keys are created; a
    /// unique suffix ensures every seal gets its own fresh Secure Enclave key.
    private static let sealingKeyTagPrefix = "com.ory.client.deviceauthn.pin-sealing."

    /// The ECIES algorithm for the outer Secure Enclave wrap. Its authenticity covers only
    /// the hardware binding: an unwrap failure reveals a damaged blob or missing key, never
    /// whether a PIN was right.
    private static let sealingAlgorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

    private let sealingKeyProvider: any OryPINSealingKeyProvider

    init(sealingKeyProvider: any OryPINSealingKeyProvider = OrySecureEnclavePINSealingKeyProvider()) {
        self.sealingKeyProvider = sealingKeyProvider
    }

    // MARK: - Transport key

    func makeTransportKey() -> TransportKey {
        TransportKey(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    /// The attestation challenge for a PIN-protected enrollment: `SHA256(nonce ‖
    /// transport_public_key)`. Binding the transport key into the attested challenge stops a
    /// session-level attacker from swapping in a transport key they control. The server
    /// derives the same value (`deviceauthnprotocol.Enrollment.effectiveChallenge`), so a
    /// plain-nonce attestation is rejected as "wrong challenge". Non-PIN enrollments attest
    /// the bare nonce and must not call this.
    func enrollmentChallenge(nonce: Data, transportKey: TransportKey) -> Data {
        var input = nonce
        input.append(transportKey.publicKey)
        return Data(SHA256.hash(data: input))
    }

    /// The possession-proof challenge for a PIN secret rotation: the raw concatenation
    /// `nonce ‖ transport_public_key`. The device signs this with its enrolled signing key
    /// (via the same assertion path as login) to prove it still holds the key and to bind the
    /// freshly issued secret to this transport key. Unlike ``enrollmentChallenge(nonce:transportKey:)``
    /// the bytes are **not** hashed: rotation has no attestation to embed a hash in, so the
    /// server verifies the assertion over this exact concatenation
    /// (`deviceauthnprotocol`'s `slices.Concat(nonce, t_pub)`).
    func rotationChallenge(nonce: Data, transportKey: TransportKey) -> Data {
        var challenge = nonce
        challenge.append(transportKey.publicKey)
        return challenge
    }

    /// Opens the HPKE-sealed `pin_secret` returned by the server at enrollment. The AAD is
    /// the cleartext `client_key_id`, matching the server's seal.
    ///
    /// Uses ``OryHPKE`` — the package's own RFC 9180 receiver — because CryptoKit ships
    /// HPKE only from iOS 17 while the package runs from iOS 14. The tests verify it
    /// against CryptoKit's implementation where available.
    func openSealedPINSecret(
        enc: Data,
        ciphertext: Data,
        transportKey: TransportKey,
        clientKeyID: String
    ) throws -> Data {
        do {
            return try OryHPKE.open(
                encapsulatedKey: enc,
                ciphertext: ciphertext,
                recipientPrivateKey: transportKey.privateKey,
                info: Self.hpkeInfo,
                authenticating: Data(clientKeyID.utf8)
            )
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
        }
    }

    // MARK: - PIN at rest

    /// Seals `pinSecret` for storage: AES-CTR under an Argon2id key derived from `pin`
    /// (fresh salt and IV), then an ECIES wrap under a freshly created Secure Enclave
    /// sealing key so the blob is useless off this device. `pin` and `pinSecret` are
    /// zeroized before this returns — neither may outlive the seal ceremony.
    func protect(pinSecret: inout [UInt8], pin: inout [UInt8]) throws -> OryProtectedPINSecret {
        defer {
            Self.zeroize(&pinSecret)
            Self.zeroize(&pin)
        }

        let parameters = Sodium().pwHash
        let salt = try Self.randomBytes(count: parameters.SaltBytes)
        let iv = try Self.randomBytes(count: kCCBlockSizeAES128)
        let opsLimit = parameters.OpsLimitInteractive
        let memLimit = parameters.MemLimitInteractive

        var pinKey = try Self.deriveKey(pin: &pin, salt: salt, opsLimit: opsLimit, memLimit: memLimit)
        defer { Self.zeroize(&pinKey) }

        let inner = try Self.aesCTR(key: pinKey, iv: iv, data: pinSecret)
        let tag = Self.sealingKeyTagPrefix + UUID().uuidString
        let sealed = try wrap(Data(inner), tag: tag)

        return OryProtectedPINSecret(
            version: 1,
            salt: salt,
            iv: iv,
            opsLimit: opsLimit,
            memLimit: memLimit,
            sealingKeyTag: tag,
            sealed: sealed
        )
    }

    /// Recovers the stored `pin_secret` with `pin`. `pin` is zeroized before this returns;
    /// the caller owns zeroizing the returned bytes once the `pin_proof` is computed.
    ///
    /// **A wrong PIN does not fail.** The unauthenticated AES-CTR layer decrypts to a
    /// well-formed but wrong secret, whose `pin_proof` the server rejects — advancing the
    /// key's `pin_max_attempts` counter and locking the key at the limit. The client must
    /// never validate the PIN locally; the server is the only PIN oracle.
    ///
    /// A missing sealing key or an undecryptable blob is structural, independent of the
    /// PIN, and surfaces as ``OryClientError/deviceAuthenticationNotEnrolled``: the PIN
    /// material is unusable and the user must enroll the PIN again.
    func unlock(_ protected: OryProtectedPINSecret, pin: inout [UInt8]) throws -> [UInt8] {
        defer { Self.zeroize(&pin) }

        guard let sealingKey = try sealingKeyProvider.key(tag: protected.sealingKeyTag) else {
            throw OryClientError.deviceAuthenticationNotEnrolled
        }
        var unwrapError: Unmanaged<CFError>?
        guard let inner = SecKeyCreateDecryptedData(sealingKey, Self.sealingAlgorithm, protected.sealed as CFData, &unwrapError) as Data? else {
            throw OryClientError.deviceAuthenticationNotEnrolled
        }

        var pinKey = try Self.deriveKey(
            pin: &pin,
            salt: protected.salt,
            opsLimit: protected.opsLimit,
            memLimit: protected.memLimit
        )
        defer { Self.zeroize(&pinKey) }

        return try Self.aesCTR(key: pinKey, iv: protected.iv, data: Array(inner))
    }

    /// Removes the Secure Enclave sealing key behind `protected`, once the material it
    /// wraps is replaced or forgotten. Best-effort; a missing key is not an error.
    func deleteSealingKey(_ protected: OryProtectedPINSecret) {
        sealingKeyProvider.deleteKey(tag: protected.sealingKeyTag)
    }

    // MARK: - pin_proof

    /// `HMAC-SHA256(pin_secret, domain ‖ client_key_id ‖ nonce)` — the login proof.
    func proof(pinSecret: some ContiguousBytes, clientKeyID: String, nonce: Data) -> Data {
        var message = Self.pinProofDomain
        message.append(Data(clientKeyID.utf8))
        message.append(nonce)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: pinSecret))
        return Data(mac)
    }

    // MARK: - Argon2id (libsodium)

    /// Derives a 32-byte AES key from the PIN with Argon2id, the KDF the client guide
    /// mandates. The parameters are libsodium's interactive tier, persisted per seal so a
    /// future tier change cannot break existing blobs. `pin` is zeroized before this
    /// returns, whether derivation succeeds or fails. Internal (not private) so tests can
    /// pin it to a reference Argon2id vector.
    static func deriveKey(pin: inout [UInt8], salt: Data, opsLimit: Int, memLimit: Int) throws -> [UInt8] {
        defer { zeroize(&pin) }
        guard let key = Sodium().pwHash.hash(
            outputLength: 32,
            passwd: pin,
            salt: Array(salt),
            opsLimit: opsLimit,
            memLimit: memLimit,
            alg: .Argon2ID13
        ) else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.keyDerivationFailed)
        }
        return key
    }

    // MARK: - AES-CTR (CommonCrypto)

    /// Unauthenticated AES-CTR; encryption and decryption are the same operation. Internal
    /// (not private) so tests can pin it to the NIST SP 800-38A vectors.
    static func aesCTR(key: [UInt8], iv: Data, data: [UInt8]) throws -> [UInt8] {
        guard iv.count == kCCBlockSizeAES128 else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.malformedProtectedSecret)
        }

        var cryptor: CCCryptorRef?
        let createStatus = iv.withUnsafeBytes { ivBuffer in
            key.withUnsafeBytes { keyBuffer in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES128),
                    CCPadding(ccNoPadding),
                    ivBuffer.baseAddress,
                    keyBuffer.baseAddress,
                    keyBuffer.count,
                    nil,
                    0,
                    0,
                    0,
                    &cryptor
                )
            }
        }
        guard createStatus == kCCSuccess, let cryptor else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.cipherFailed(status: Int(createStatus)))
        }
        defer { CCCryptorRelease(cryptor) }

        var output = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        let updateStatus = data.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                CCCryptorUpdate(
                    cryptor,
                    inBuffer.baseAddress,
                    inBuffer.count,
                    outBuffer.baseAddress,
                    outBuffer.count,
                    &moved
                )
            }
        }
        guard updateStatus == kCCSuccess, moved == data.count else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.cipherFailed(status: Int(updateStatus)))
        }
        return output
    }

    // MARK: - Secure Enclave wrap

    private func wrap(_ plaintext: Data, tag: String) throws -> Data {
        let key = try sealingKeyProvider.createKey(tag: tag)
        guard let publicKey = SecKeyCopyPublicKey(key) else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.sealingKeyUnusable)
        }
        var error: Unmanaged<CFError>?
        guard let sealed = SecKeyCreateEncryptedData(publicKey, Self.sealingAlgorithm, plaintext as CFData, &error) as Data? else {
            // The freshly created key is unusable; do not leave it behind.
            sealingKeyProvider.deleteKey(tag: tag)
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error!.takeRetainedValue() as Error))
        }
        return sealed
    }

    // MARK: - Helpers

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw OryClientError.deviceAuthenticationFailed(underlying: PINVaultError.randomBytesFailed)
        }
        return Data(bytes)
    }

    /// Overwrites sensitive bytes in place. The PIN, the derived key, and the recovered
    /// secret must not outlive the seal/unseal ceremony.
    static func zeroize(_ bytes: inout [UInt8]) {
        for i in bytes.indices {
            bytes[i] = 0
        }
    }
}

private enum PINVaultError: Error, Sendable, LocalizedError {
    case keyDerivationFailed
    case cipherFailed(status: Int)
    case sealingKeyUnusable
    case malformedProtectedSecret
    case randomBytesFailed

    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed:
            return "PIN key derivation failed."
        case let .cipherFailed(status):
            return "The PIN secret cipher failed (status \(status))."
        case .sealingKeyUnusable:
            return "The PIN sealing key could not be used."
        case .malformedProtectedSecret:
            return "The stored PIN secret is malformed."
        case .randomBytesFailed:
            return "Generating random bytes failed."
        }
    }
}
