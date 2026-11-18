import CryptoKit
import Foundation

/// Minimal RFC 9180 HPKE for the one configuration the Ory backend uses to deliver the
/// `pin_secret`: DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-128-GCM, base mode, a
/// single message (sequence number 0).
///
/// CryptoKit ships HPKE only from iOS 17 while this package runs from iOS 14, so the
/// receiver side is implemented here on CryptoKit's long-available primitives (X25519
/// key agreement, HMAC-SHA256, AES-GCM). HKDF is spelled out via HMAC rather than
/// CryptoKit's `HKDF` type because RFC 9180 needs the separate extract and expand
/// stages. Only the receiver ships: the sender exists for the package's tests, which
/// emulate the server and verify interoperability against CryptoKit's HPKE where it is
/// available, and is compiled out of release builds.
enum OryHPKE {

    /// `Nk` (AES-128-GCM key), `Nn` (nonce), and `Nsecret` (HKDF-SHA256) per RFC 9180 §7.
    private static let keyByteCount = 16
    private static let nonceByteCount = 12
    private static let sharedSecretByteCount = 32
    private static let tagByteCount = 16

    /// `suite_id` for the key-schedule labels: `"HPKE" ‖ kem_id ‖ kdf_id ‖ aead_id`
    /// (0x0020 DHKEM(X25519, HKDF-SHA256), 0x0001 HKDF-SHA256, 0x0001 AES-128-GCM).
    private static let hpkeSuiteID = Data("HPKE".utf8) + Data([0x00, 0x20, 0x00, 0x01, 0x00, 0x01])

    /// `suite_id` for the DHKEM labels: `"KEM" ‖ kem_id`.
    private static let kemSuiteID = Data("KEM".utf8) + Data([0x00, 0x20])

    enum HPKEError: Error, Sendable {
        case malformedCiphertext
    }

    /// Opens `ciphertext` (AEAD ciphertext followed by its 16-byte tag, as HPKE puts it
    /// on the wire) sealed to `recipientPrivateKey` under `enc`, binding `aad`.
    static func open(
        encapsulatedKey: Data,
        ciphertext: Data,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        info: Data,
        authenticating aad: Data
    ) throws -> Data {
        guard ciphertext.count >= tagByteCount else {
            throw HPKEError.malformedCiphertext
        }
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: encapsulatedKey)
        let dh = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let sharedSecret = deriveSharedSecret(
            dh: dh,
            encapsulatedKey: encapsulatedKey,
            recipientPublicKey: recipientPrivateKey.publicKey.rawRepresentation
        )
        let (key, nonce) = keySchedule(sharedSecret: sharedSecret, info: info)

        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext.dropLast(tagByteCount),
            tag: ciphertext.suffix(tagByteCount)
        )
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    #if DEBUG
    /// Seals `message` to `recipientPublicKey` (raw X25519 bytes), binding `aad` —
    /// the sender side, mirroring the backend's one-time `pin_secret` delivery.
    /// Debug-only: the client never seals, so this must not reach a release build.
    static func seal(
        _ message: Data,
        recipientPublicKey: Data,
        info: Data,
        authenticating aad: Data
    ) throws -> (encapsulatedKey: Data, ciphertext: Data) {
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let encapsulatedKey = ephemeral.publicKey.rawRepresentation
        let dh = try ephemeral.sharedSecretFromKeyAgreement(with: recipientKey)
        let sharedSecret = deriveSharedSecret(
            dh: dh,
            encapsulatedKey: encapsulatedKey,
            recipientPublicKey: recipientPublicKey
        )
        let (key, nonce) = keySchedule(sharedSecret: sharedSecret, info: info)

        let box = try AES.GCM.seal(message, using: key, nonce: AES.GCM.Nonce(data: nonce), authenticating: aad)
        return (encapsulatedKey, box.ciphertext + box.tag)
    }
    #endif

    /// DHKEM `ExtractAndExpand` (RFC 9180 §4.1): the KEM shared secret from the raw DH
    /// output and `kem_context = enc ‖ pkR`.
    private static func deriveSharedSecret(dh: SharedSecret, encapsulatedKey: Data, recipientPublicKey: Data) -> Data {
        let dhBytes = dh.withUnsafeBytes { Data($0) }
        let eaePRK = labeledExtract(salt: Data(), suiteID: kemSuiteID, label: "eae_prk", keyMaterial: dhBytes)
        return labeledExpand(
            pseudoRandomKey: eaePRK,
            suiteID: kemSuiteID,
            label: "shared_secret",
            info: encapsulatedKey + recipientPublicKey,
            outputByteCount: sharedSecretByteCount
        )
    }

    /// `KeySchedule` for `mode_base` (0x00, no PSK), RFC 9180 §5.1. Returns the AEAD key
    /// and `base_nonce`; with a single message the sequence number is 0, so `base_nonce`
    /// is the nonce.
    private static func keySchedule(sharedSecret: Data, info: Data) -> (key: SymmetricKey, nonce: Data) {
        let pskIDHash = labeledExtract(salt: Data(), suiteID: hpkeSuiteID, label: "psk_id_hash", keyMaterial: Data())
        let infoHash = labeledExtract(salt: Data(), suiteID: hpkeSuiteID, label: "info_hash", keyMaterial: info)
        var context = Data([0x00])
        context.append(pskIDHash)
        context.append(infoHash)

        let secret = labeledExtract(salt: sharedSecret, suiteID: hpkeSuiteID, label: "secret", keyMaterial: Data())
        let key = labeledExpand(pseudoRandomKey: secret, suiteID: hpkeSuiteID, label: "key", info: context, outputByteCount: keyByteCount)
        let baseNonce = labeledExpand(pseudoRandomKey: secret, suiteID: hpkeSuiteID, label: "base_nonce", info: context, outputByteCount: nonceByteCount)
        return (SymmetricKey(data: key), baseNonce)
    }

    /// `LabeledExtract` (RFC 9180 §4): HKDF-Extract with the labeled key material
    /// `"HPKE-v1" ‖ suite_id ‖ label ‖ ikm`.
    private static func labeledExtract(salt: Data, suiteID: Data, label: String, keyMaterial: Data) -> Data {
        var labeled = Data("HPKE-v1".utf8)
        labeled.append(suiteID)
        labeled.append(Data(label.utf8))
        labeled.append(keyMaterial)
        return hkdfExtract(salt: salt, keyMaterial: labeled)
    }

    /// `LabeledExpand` (RFC 9180 §4): HKDF-Expand with the labeled info
    /// `I2OSP(L, 2) ‖ "HPKE-v1" ‖ suite_id ‖ label ‖ info`.
    private static func labeledExpand(pseudoRandomKey: Data, suiteID: Data, label: String, info: Data, outputByteCount: Int) -> Data {
        var labeledInfo = Data([UInt8(outputByteCount >> 8), UInt8(outputByteCount & 0xFF)])
        labeledInfo.append(Data("HPKE-v1".utf8))
        labeledInfo.append(suiteID)
        labeledInfo.append(Data(label.utf8))
        labeledInfo.append(info)
        return hkdfExpand(pseudoRandomKey: pseudoRandomKey, info: labeledInfo, outputByteCount: outputByteCount)
    }

    /// HKDF-Extract (RFC 5869): `HMAC-SHA256(salt, ikm)`. An empty salt stands for the
    /// RFC's string of hash-length zero bytes — HMAC pads the key with zeros, so the two
    /// are equivalent.
    private static func hkdfExtract(salt: Data, keyMaterial: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: keyMaterial, using: SymmetricKey(data: salt)))
    }

    /// HKDF-Expand (RFC 5869): `T(i) = HMAC(prk, T(i-1) ‖ info ‖ i)` concatenated to the
    /// requested length. Every length this file needs fits in well under 255 blocks.
    private static func hkdfExpand(pseudoRandomKey: Data, info: Data, outputByteCount: Int) -> Data {
        let key = SymmetricKey(data: pseudoRandomKey)
        var output = Data()
        var previousBlock = Data()
        var counter: UInt8 = 1
        while output.count < outputByteCount {
            var message = previousBlock
            message.append(info)
            message.append(counter)
            previousBlock = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
            output.append(previousBlock)
            counter += 1
        }
        return output.prefix(outputByteCount)
    }
}
