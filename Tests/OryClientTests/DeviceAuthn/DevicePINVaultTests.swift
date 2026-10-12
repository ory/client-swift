import CryptoKit
import Foundation
import OryClientTestDoubles
import Testing
@testable import OryClient

@Suite("Device PIN vault")
struct DevicePINVaultTests {

    private let sealingKeys = InsecureEphemeralPINSealingKeyProvider()
    private var vault: DevicePINVault { DevicePINVault(sealingKeyProvider: sealingKeys) }

    // The info string must match the backend (deviceauthnprotocol/hpke.go). The test
    // re-declares it so a drift in the vault's constant breaks the round-trip below.
    // The HPKE suite itself is pinned against CryptoKit's implementation in OryHPKETests.
    private let info = Data("ory/deviceauthn/pin-secret/v1".utf8)

    // MARK: - HPKE unseal

    @Test("openSealedPINSecret opens a secret sealed to the transport key with client_key_id as AAD")
    func opensSealedSecret() throws {
        // Given a server-style HPKE seal to the device's transport public key
        let transport = vault.makeTransportKey()
        let clientKeyID = "abc123"
        let pinSecret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        let sealed = try OryHPKE.seal(
            pinSecret,
            recipientPublicKey: transport.publicKey,
            info: info,
            authenticating: Data(clientKeyID.utf8)
        )

        // When the vault opens it
        let opened = try vault.openSealedPINSecret(
            enc: sealed.encapsulatedKey,
            ciphertext: sealed.ciphertext,
            transportKey: transport,
            clientKeyID: clientKeyID
        )

        // Then the pin_secret is recovered
        #expect(opened == pinSecret)
    }

    @Test("openSealedPINSecret fails when the client_key_id AAD differs")
    func rejectsWrongAAD() throws {
        let transport = vault.makeTransportKey()
        let pinSecret = Data(repeating: 7, count: 32)
        let sealed = try OryHPKE.seal(
            pinSecret,
            recipientPublicKey: transport.publicKey,
            info: info,
            authenticating: Data("expected-id".utf8)
        )

        #expect(throws: OryClientError.self) {
            try vault.openSealedPINSecret(
                enc: sealed.encapsulatedKey,
                ciphertext: sealed.ciphertext,
                transportKey: transport,
                clientKeyID: "wrong-id"
            )
        }
    }

    // MARK: - PIN at rest

    @Test("protect then unlock with the correct PIN recovers the secret")
    func protectUnlockRoundTrip() throws {
        let pinSecret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        let protected = try vault.protect(pinSecret: pinSecret, pinString: "1234")
        let recovered = try vault.unlock(protected, pinString: "1234")

        #expect(recovered == pinSecret)
    }

    @Test("a wrong PIN yields plausible garbage, never a locally detectable failure")
    func wrongPINYieldsWellFormedGarbage() throws {
        // The inner AES-CTR layer is deliberately unauthenticated: the client must not be
        // able to tell a wrong PIN apart locally. The wrong-but-well-formed secret produces
        // a wrong-but-well-formed pin_proof, which is sent to the server — the only PIN
        // oracle — where it advances the pin_max_attempts counter.
        let pinSecret = Data(repeating: 1, count: 32)
        let protected = try vault.protect(pinSecret: pinSecret, pinString: "1234")

        let garbage = try vault.unlock(protected, pinString: "9999")

        #expect(garbage.count == pinSecret.count)
        #expect(garbage != pinSecret)

        // The proof over the garbage secret is structurally indistinguishable from a real
        // one — 32 HMAC bytes — but does not verify against the real secret's proof.
        let nonce = Data("nonce".utf8)
        let wrongProof = vault.proof(pinSecret: garbage, clientKeyID: "key", nonce: nonce)
        let rightProof = vault.proof(pinSecret: pinSecret, clientKeyID: "key", nonce: nonce)
        #expect(wrongProof.count == rightProof.count)
        #expect(wrongProof != rightProof)
    }

    @Test("protect uses a fresh salt, IV, and sealing key each time")
    func freshSaltIVAndSealingKeyPerProtect() throws {
        // Reusing salt or IV across seals would leak the secret via CTR keystream reuse;
        // the sealing key is one-per-seal by design.
        let secret = Data(repeating: 2, count: 32)
        let a = try vault.protect(pinSecret: secret, pinString: "1234")
        let b = try vault.protect(pinSecret: secret, pinString: "1234")

        #expect(a.salt != b.salt)
        #expect(a.iv != b.iv)
        #expect(a.sealed != b.sealed)
        #expect(a.sealingKeyTag != b.sealingKeyTag)
        #expect(sealingKeys.storedTags.isSuperset(of: [a.sealingKeyTag, b.sealingKeyTag]))
    }

    @Test("protect records the Argon2id parameters and recipe version it sealed with")
    func protectPersistsKDFParameters() throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 3, count: 32), pinString: "1234")

        #expect(protected.version == 1)
        #expect(protected.salt.count == 16)
        #expect(protected.iv.count == 16)
        // libsodium's interactive tier: 2 passes over 64 MiB. Persisted so a future tier
        // change cannot break existing blobs.
        #expect(protected.opsLimit == 2)
        #expect(protected.memLimit == 67_108_864)
        #expect(!protected.sealingKeyTag.isEmpty)
    }

    @Test("a blob without its sealing key is structural and routes to re-enrollment")
    func sealedBlobRequiresSealingKey() throws {
        // A blob exfiltrated from the Keychain must be useless without this device's
        // Secure Enclave key. The failure is structural — independent of the PIN — and
        // surfaces as notEnrolled so callers route the user to enroll the PIN again.
        let protected = try vault.protect(pinSecret: Data(repeating: 4, count: 32), pinString: "1234")

        let otherDevice = DevicePINVault(sealingKeyProvider: InsecureEphemeralPINSealingKeyProvider())
        do {
            _ = try otherDevice.unlock(protected, pinString: "1234")
            Issue.record("expected unlock without the sealing key to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
    }

    @Test("deleteSealingKey removes the key behind the artifacts")
    func deleteSealingKeyRemovesKey() throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 4, count: 32), pinString: "1234")

        vault.deleteSealingKey(protected)

        #expect(sealingKeys.deletedTags == [protected.sealingKeyTag])
        do {
            _ = try vault.unlock(protected, pinString: "1234")
            Issue.record("expected unlock after key deletion to throw")
        } catch let error as OryClientError {
            #expect(error.isDeviceAuthenticationNotEnrolled)
        }
    }

    @Test("protect zeroizes the PIN and secret bytes it was given")
    func protectZeroizesPINAndSecret() throws {
        var pin = Array("1234".utf8)
        var secret = [UInt8](repeating: 5, count: 32)

        _ = try vault.protect(pinSecret: &secret, pin: &pin)

        #expect(pin.allSatisfy { $0 == 0 })
        #expect(secret.allSatisfy { $0 == 0 })
    }

    @Test("unlock zeroizes the PIN bytes it was given")
    func unlockZeroizesPIN() throws {
        let protected = try vault.protect(pinSecret: Data(repeating: 5, count: 32), pinString: "1234")
        var pin = Array("1234".utf8)

        _ = try vault.unlock(protected, pin: &pin)

        #expect(pin.allSatisfy { $0 == 0 })
    }

    // MARK: - Argon2id

    @Test("deriveKey matches the reference Argon2id implementation")
    func argon2idMatchesReferenceVector() throws {
        // Golden vectors from the P-H-C reference implementation (the `argon2` CLI):
        //   echo -n "<pin>" | argon2 "0123456789abcdef" -id -t 2 -k 65536 -p 1 -l 32 -r
        // Argon2id v1.3, 2 passes over 64 MiB, 1 lane — exactly libsodium's interactive
        // tier that `protect` seals with. A match proves the KDF is genuine Argon2id with
        // these parameters, not another algorithm or variant.
        let salt = Data("0123456789abcdef".utf8)

        var pin = Array("1234".utf8)
        let key = try DevicePINVault.deriveKey(pin: &pin, salt: salt, opsLimit: 2, memLimit: 67_108_864)
        #expect(Data(key) == Data(hex: "01c7b57b78e5acc679dae4ae9fcd60132c831c8b50d52af22b779d68c10df0e1"))
        #expect(pin.allSatisfy { $0 == 0 })

        var otherPIN = Array("9999".utf8)
        let otherKey = try DevicePINVault.deriveKey(pin: &otherPIN, salt: salt, opsLimit: 2, memLimit: 67_108_864)
        #expect(Data(otherKey) == Data(hex: "d58c2f65e88ac4f6fbc395e0ff8e392970008ee53c4c14c5ca8c2fa110564a6f"))
    }

    // MARK: - AES-CTR

    @Test("aesCTR matches the NIST SP 800-38A AES-256-CTR vectors")
    func aesCTRMatchesNISTVectors() throws {
        // NIST SP 800-38A, F.5.5 (CTR-AES256.Encrypt). Four consecutive blocks prove both
        // the cipher and the big-endian counter increment.
        let key: [UInt8] = Array(Data(hex: "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
        let iv = Data(hex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        let plaintext = Data(hex: """
            6bc1bee22e409f96e93d7e117393172a\
            ae2d8a571e03ac9c9eb76fac45af8e51\
            30c81c46a35ce411e5fbc1191a0a52ef\
            f69f2445df4f9b17ad2b417be66c3710
            """)
        let expected = Data(hex: """
            601ec313775789a5b7a7f504bbf3d228\
            f443e3ca4d62b59aca84e990cacaf5c5\
            2b0930daa23de94ce87017ba2d84988d\
            dfc9c58db67aada613c2dd08457941a6
            """)

        let ciphertext = try DevicePINVault.aesCTR(key: key, iv: iv, data: Array(plaintext))
        #expect(ciphertext == Array(expected))

        // CTR is its own inverse.
        #expect(try DevicePINVault.aesCTR(key: key, iv: iv, data: ciphertext) == Array(plaintext))
    }

    // MARK: - Challenge binding

    @Test("enrollmentChallenge is SHA256(nonce ‖ transport_public_key)")
    func enrollmentChallengeIsHashedConcat() {
        let transport = vault.makeTransportKey()
        let nonce = Data("nonce".utf8)

        let challenge = vault.enrollmentChallenge(nonce: nonce, transportKey: transport)

        #expect(challenge == Data(SHA256.hash(data: nonce + transport.publicKey)))
        #expect(challenge.count == 32)
    }

    @Test("rotationChallenge is the raw nonce ‖ transport_public_key, not hashed")
    func rotationChallengeIsRawConcat() {
        let transport = vault.makeTransportKey()
        let nonce = Data("nonce".utf8)

        let challenge = vault.rotationChallenge(nonce: nonce, transportKey: transport)

        var expected = nonce
        expected.append(transport.publicKey)
        #expect(challenge == expected)
        #expect(challenge.count == nonce.count + transport.publicKey.count)
        // Enrollment hashes the binding, rotation does not — the two must never coincide.
        #expect(challenge != vault.enrollmentChallenge(nonce: nonce, transportKey: transport))
    }

    // MARK: - pin_proof

    @Test("proof is deterministic and sensitive to every input")
    func proofDeterministicAndSensitive() {
        let secret = Data(repeating: 3, count: 32)
        let base = vault.proof(pinSecret: secret, clientKeyID: "key", nonce: Data("nonce".utf8))

        #expect(base.count == 32)
        #expect(vault.proof(pinSecret: secret, clientKeyID: "key", nonce: Data("nonce".utf8)) == base)
        #expect(vault.proof(pinSecret: secret, clientKeyID: "other", nonce: Data("nonce".utf8)) != base)
        #expect(vault.proof(pinSecret: secret, clientKeyID: "key", nonce: Data("other".utf8)) != base)
        #expect(vault.proof(pinSecret: Data(repeating: 4, count: 32), clientKeyID: "key", nonce: Data("nonce".utf8)) != base)
    }
}
