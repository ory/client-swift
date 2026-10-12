import CryptoKit
import Foundation
import Testing
@testable import OryClient

@Suite("OryHPKE")
struct OryHPKETests {

    private let info = Data("ory/deviceauthn/pin-secret/v1".utf8)
    private let aad = Data("client-key-id".utf8)

    /// RFC 9180 Appendix A.1, the test vector for the suite the backend uses:
    /// DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-128-GCM, base mode, sequence 0.
    private enum Vector {
        static let info = Data(hex: "4f6465206f6e2061204772656369616e2055726e")
        static let recipientPrivateKey = Data(hex: "4612c550263fc8ad58375df3f557aac531d26850903e55a9f23f21d8534e8ac8")
        static let encapsulatedKey = Data(hex: "37fda3567bdbd628e88668c3c8d7e97d1d1253b6d4ea6d44c150f741f1bf4431")
        static let aad = Data(hex: "436f756e742d30")
        static let ciphertext = Data(hex: "f938558b5d72f1a23810b4be2ab4f84331acc02fc97babc53a52ae8218a355a96d8770ac83d07bea87e13c512a")
        static let plaintext = Data(hex: "4265617574792069732074727574682c20747275746820626561757479")
    }

    // MARK: - RFC 9180 known-answer test

    // The only pin that runs below iOS 17, where the CryptoKit interop tests below
    // cannot — and where the receiver is the sole implementation available.

    @Test("Open reproduces the RFC 9180 A.1 plaintext")
    func rfc9180BaseVector() throws {
        let recipient = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Vector.recipientPrivateKey)

        let opened = try OryHPKE.open(
            encapsulatedKey: Vector.encapsulatedKey,
            ciphertext: Vector.ciphertext,
            recipientPrivateKey: recipient,
            info: Vector.info,
            authenticating: Vector.aad
        )

        #expect(opened == Vector.plaintext)
    }

    @Test("Seal then open round-trips")
    func roundTrip() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let message = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        let sealed = try OryHPKE.seal(
            message,
            recipientPublicKey: recipient.publicKey.rawRepresentation,
            info: info,
            authenticating: aad
        )
        let opened = try OryHPKE.open(
            encapsulatedKey: sealed.encapsulatedKey,
            ciphertext: sealed.ciphertext,
            recipientPrivateKey: recipient,
            info: info,
            authenticating: aad
        )

        #expect(opened == message)
    }

    @Test("Open rejects a different AAD")
    func wrongAAD() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try OryHPKE.seal(
            Data("secret".utf8),
            recipientPublicKey: recipient.publicKey.rawRepresentation,
            info: info,
            authenticating: aad
        )

        #expect(throws: (any Error).self) {
            try OryHPKE.open(
                encapsulatedKey: sealed.encapsulatedKey,
                ciphertext: sealed.ciphertext,
                recipientPrivateKey: recipient,
                info: info,
                authenticating: Data("other-key-id".utf8)
            )
        }
    }

    @Test("Open rejects a tampered ciphertext")
    func tamperedCiphertext() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try OryHPKE.seal(
            Data("secret".utf8),
            recipientPublicKey: recipient.publicKey.rawRepresentation,
            info: info,
            authenticating: aad
        )
        var tampered = sealed.ciphertext
        tampered[tampered.startIndex] ^= 0x01

        #expect(throws: (any Error).self) {
            try OryHPKE.open(
                encapsulatedKey: sealed.encapsulatedKey,
                ciphertext: tampered,
                recipientPrivateKey: recipient,
                info: info,
                authenticating: aad
            )
        }
    }

    @Test("Open rejects the wrong recipient key")
    func wrongRecipient() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try OryHPKE.seal(
            Data("secret".utf8),
            recipientPublicKey: recipient.publicKey.rawRepresentation,
            info: info,
            authenticating: aad
        )

        #expect(throws: (any Error).self) {
            try OryHPKE.open(
                encapsulatedKey: sealed.encapsulatedKey,
                ciphertext: sealed.ciphertext,
                recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey(),
                info: info,
                authenticating: aad
            )
        }
    }

    @Test("Open rejects a ciphertext shorter than the AEAD tag")
    func truncatedCiphertext() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()

        #expect(throws: OryHPKE.HPKEError.self) {
            try OryHPKE.open(
                encapsulatedKey: recipient.publicKey.rawRepresentation,
                ciphertext: Data(repeating: 0, count: 15),
                recipientPrivateKey: recipient,
                info: info,
                authenticating: aad
            )
        }
    }

    // MARK: - Interop with CryptoKit's HPKE (the reference implementation)

    // Both directions, so a divergence from RFC 9180 cannot pass unnoticed. Reported as
    // skipped below iOS 17 / macOS 14 rather than silently passing.

    private static let cryptoKitHPKEAvailable: Bool = {
        if #available(iOS 17.0, macOS 14.0, *) { true } else { false }
    }()

    @Test(
        "CryptoKit's sender interoperates with OryHPKE's receiver",
        .enabled(if: cryptoKitHPKEAvailable, "CryptoKit's HPKE needs iOS 17 / macOS 14")
    )
    func opensCryptoKitSeal() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let message = Data("sealed by CryptoKit, opened by OryHPKE".utf8)

        let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_128)
        var sender = try HPKE.Sender(recipientKey: recipient.publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(message, authenticating: aad)

        let opened = try OryHPKE.open(
            encapsulatedKey: sender.encapsulatedKey,
            ciphertext: ciphertext,
            recipientPrivateKey: recipient,
            info: info,
            authenticating: aad
        )

        #expect(opened == message)
    }

    @Test(
        "CryptoKit's receiver interoperates with OryHPKE's sender",
        .enabled(if: cryptoKitHPKEAvailable, "CryptoKit's HPKE needs iOS 17 / macOS 14")
    )
    func cryptoKitOpensOurSeal() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let message = Data("sealed by OryHPKE, opened by CryptoKit".utf8)

        let sealed = try OryHPKE.seal(
            message,
            recipientPublicKey: recipient.publicKey.rawRepresentation,
            info: info,
            authenticating: aad
        )

        let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_128)
        var recipientContext = try HPKE.Recipient(
            privateKey: recipient,
            ciphersuite: suite,
            info: info,
            encapsulatedKey: sealed.encapsulatedKey
        )
        let opened = try recipientContext.open(sealed.ciphertext, authenticating: aad)

        #expect(opened == message)
    }
}
