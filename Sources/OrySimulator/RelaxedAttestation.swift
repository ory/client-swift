#if targetEnvironment(simulator)

import CryptoKit
import Foundation
import SwiftASN1
import X509

/// Builds a self-signed attestation chain and login signatures the Ory backend accepts
/// when "Allow relaxed attestation for testing" is enabled. This is the Simulator
/// stand-in for the Secure Enclave; it mirrors the cryptographic contract the real
/// `DCAppAttestService` fulfils on device.
enum RelaxedAttestation {

    struct Attestation: Sendable {
        let keyID: String
        let cbor: Data
        let privateKey: P256.Signing.PrivateKey
    }

    /// Creates an attestation for a fresh key, binding the server nonce into the leaf
    /// certificate the same way Apple's attestation does. `appID` (as
    /// `"<TeamID>.<BundleID>"`) fills the authenticator data's rpIdHash for projects
    /// that pin `ios_app_ids`; without it the hash is zeros, which passes only when
    /// pinning is off.
    static func create(serverNonce: Data, appID: String?) throws -> Attestation {
        let rootKey = P256.Signing.PrivateKey()
        let rootCert = try selfSignedRoot(key: rootKey)
        let rootDER = try serialize(rootCert)

        let intermediateKey = P256.Signing.PrivateKey()
        let intermediateCert = try signedIntermediate(key: intermediateKey, issuer: rootCert, issuerKey: rootKey)
        let intermediateDER = try serialize(intermediateCert)

        let leafKey = P256.Signing.PrivateKey()
        // The server derives client_key_id as the lowercase-hex SHA-256 of the enrolled
        // key's public key in PKIX ASN.1 DER (SubjectPublicKeyInfo) form and ignores any
        // client-supplied value. Derive it identically so later logins reference the same id.
        let keyID = clientKeyID(for: leafKey.publicKey)
        let authData = attestationAuthData(for: leafKey.publicKey, appID: appID)
        let certNonce = compositeNonce(authData: authData, serverNonce: serverNonce)
        let leafCert = try signedLeaf(key: leafKey, issuer: intermediateCert, issuerKey: intermediateKey, nonce: certNonce)
        let leafDER = try serialize(leafCert)

        let attestation: CBOR = .map([
            (.textString("fmt"), .textString("apple-appattest")),
            (.textString("attStmt"), .map([
                (.textString("x5c"), .array([
                    .byteString(Data(leafDER)),
                    .byteString(Data(intermediateDER)),
                    .byteString(Data(rootDER)),
                ])),
                (.textString("receipt"), .byteString(Data("dummy-receipt".utf8))),
            ])),
            (.textString("authData"), .byteString(authData)),
        ])

        return Attestation(keyID: keyID, cbor: attestation.encode(), privateKey: leafKey)
    }

    /// Signs a login challenge with the enrolled key, producing the CBOR assertion the
    /// backend verifies. The assertion's authenticator data carries the rpIdHash for
    /// `appID`, which the server checks against `ios_app_ids` when pinning is on.
    static func loginSignature(privateKey: P256.Signing.PrivateKey, clientData: Data, appID: String?) throws -> Data {
        let authenticatorData = assertionAuthData(appID: appID)
        let nonce = compositeNonce(authData: authenticatorData, serverNonce: clientData)
        let signature = try privateKey.signature(for: SHA256.hash(data: nonce))

        let payload: CBOR = .map([
            (.textString("signature"), .byteString(signature.derRepresentation)),
            (.textString("authenticatorData"), .byteString(authenticatorData)),
        ])
        return payload.encode()
    }

    // MARK: - Authenticator data

    /// The WebAuthn authenticator data of an App Attest attestation, which the server
    /// parses and validates: `rpIdHash(32) | flags(1) | signCount(4) | AAGUID(16) |
    /// credentialIdLength(2) | credentialId`. The AAGUID is the development
    /// environment's — Apple's Simulator counterpart — which the server accepts only
    /// under relaxed attestation. The credential ID must be the App Attest key
    /// identifier: the SHA-256 of the public key's uncompressed X9.62 point.
    private static func attestationAuthData(for publicKey: P256.Signing.PublicKey, appID: String?) -> Data {
        var authData = rpIDHash(appID: appID)
        // Flags: attested-credential data present.
        authData.append(0x40)
        // Signature counter: a freshly created key has never signed.
        authData.append(contentsOf: [0, 0, 0, 0])
        authData.append(Data("appattestdevelop".utf8))
        let credentialID = Data(SHA256.hash(data: publicKey.x963Representation))
        authData.append(contentsOf: [0, UInt8(credentialID.count)])
        authData.append(credentialID)
        return authData
    }

    /// The authenticator data of an App Attest assertion: `rpIdHash(32) | flags(1) |
    /// signCount(4)`. The server verifies the signature over its exact bytes and, when
    /// App ID pinning is on, checks the leading rpIdHash.
    private static func assertionAuthData(appID: String?) -> Data {
        var authData = rpIDHash(appID: appID)
        authData.append(0x00)
        authData.append(contentsOf: [0, 0, 0, 1])
        return authData
    }

    /// `SHA256("<TeamID>.<BundleID>")`, or 32 zero bytes when no App ID is given —
    /// valid whenever the project does not pin `ios_app_ids`.
    private static func rpIDHash(appID: String?) -> Data {
        guard let appID else {
            return Data(count: 32)
        }
        return Data(SHA256.hash(data: Data(appID.utf8)))
    }

    // MARK: - Key id derivation

    /// The lowercase-hex SHA-256 of the public key's PKIX ASN.1 DER (SubjectPublicKeyInfo)
    /// encoding — the exact bytes Go's `x509.MarshalPKIXPublicKey` emits for the same key.
    static func clientKeyID(for publicKey: P256.Signing.PublicKey) -> String {
        SHA256.hash(data: publicKey.derRepresentation)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Nonce

    /// SHA256(header || serverNonce), used for both the certificate nonce binding and the
    /// login signature.
    private static func compositeNonce(authData: Data, serverNonce: Data) -> Data {
        var hasher = SHA256()
        hasher.update(data: authData)
        hasher.update(data: serverNonce)
        return Data(hasher.finalize())
    }

    // MARK: - Certificates

    private static let appleAttestationOID: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 8, 2]

    private static func serialize(_ cert: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try serializer.serialize(cert)
        return Data(serializer.serializedBytes)
    }

    private static func selfSignedRoot(key: P256.Signing.PrivateKey) throws -> Certificate {
        let name = try DistinguishedName { CommonName("Test Apple Root CA") }
        let now = Date()
        return try Certificate(
            version: .v3,
            serialNumber: .init(bytes: [1]),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            },
            issuerPrivateKey: .init(key)
        )
    }

    private static func signedIntermediate(
        key: P256.Signing.PrivateKey,
        issuer: Certificate,
        issuerKey: P256.Signing.PrivateKey
    ) throws -> Certificate {
        let name = try DistinguishedName { CommonName("Apple App Attestation CA 1") }
        let now = Date()
        return try Certificate(
            version: .v3,
            serialNumber: .init(bytes: [2]),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(3600),
            issuer: issuer.subject,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
            },
            issuerPrivateKey: .init(issuerKey)
        )
    }

    private static func signedLeaf(
        key: P256.Signing.PrivateKey,
        issuer: Certificate,
        issuerKey: P256.Signing.PrivateKey,
        nonce: Data
    ) throws -> Certificate {
        let name = try DistinguishedName { CommonName("Test Device Key") }
        let now = Date()
        let nonceExtension = try appleAttestationExtension(nonce: nonce)
        return try Certificate(
            version: .v3,
            serialNumber: .init(bytes: [3]),
            publicKey: .init(key.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(3600),
            issuer: issuer.subject,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                nonceExtension
            },
            issuerPrivateKey: .init(issuerKey)
        )
    }

    /// The Apple attestation certificate extension (OID 1.2.840.113635.100.8.2):
    /// `SEQUENCE { [1] EXPLICIT OCTET STRING(nonce) }`.
    private static func appleAttestationExtension(nonce: Data) throws -> Certificate.Extension {
        var serializer = DER.Serializer()
        try serializer.appendConstructedNode(identifier: .sequence) { coder in
            try coder.appendConstructedNode(
                identifier: .init(tagWithNumber: 1, tagClass: .contextSpecific)
            ) { inner in
                try inner.serialize(ASN1OctetString(contentBytes: ArraySlice(nonce)))
            }
        }
        return .init(oid: appleAttestationOID, critical: false, value: serializer.serializedBytes[...])
    }
}

#endif
