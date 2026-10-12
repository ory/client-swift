import Foundation
import Testing
@testable import OryClient

@Suite("Attested device key ID")
struct AttestedDeviceKeyIDTests {

    private var leaf: Data { Fixture.load("ios-attestation-leaf", extension: "der") }

    @Test("Real Apple attestation matches the backend SPKI fingerprint")
    func appleAttestationFingerprint() throws {
        // Given the backend's public Apple attestation fixture and an OpenSSL-derived ID.
        // When the key is extracted, certificate expiry does not change its identity.
        let fingerprint = try AttestedDeviceKeyID.derive(from: Fixture.deviceAttestation)

        // Then the ID matches Go's SHA256(x509.MarshalPKIXPublicKey(leaf.PublicKey)).
        #expect(fingerprint == Fixture.attestedClientKeyID)
    }

    @Test("Malformed CBOR cannot produce a device ID", arguments: [
        Data(), Data([0xa0]), Data([0xa1]), Data([0xbf, 0xff]),
        Data([0xba, 0xff, 0xff, 0xff, 0xff]),
        Data([0xbb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        Data([0x7b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        Data([0xa1, 0x61, 0xff, 0x00]),
    ])
    func malformedCBOR(data: Data) {
        #expect(throws: (any Error).self) {
            try AttestedDeviceKeyID.derive(from: data)
        }
    }

    @Test("Truncated attestation and trailing data are rejected", arguments: [false, true])
    func incompleteOrTrailingData(trailing: Bool) {
        let data = trailing ? Fixture.deviceAttestation + Data([0x00]) : Fixture.deviceAttestation.dropLast()
        #expect(throws: (any Error).self) {
            try AttestedDeviceKeyID.derive(from: data)
        }
    }

    @Test("Field order and unused fields do not change the key fingerprint")
    func reorderedFields() throws {
        // Given the same public certificate surrounded by unused CBOR values.
        let data = CBORFixture.map([
            ("unused", Data([0x83, 0xf5, 0xc1, 0x00, 0x20])),
            ("attStmt", CBORFixture.map([
                ("receipt", CBORFixture.bytes(Data([1, 2, 3]))),
                ("x5c", CBORFixture.array([CBORFixture.bytes(leaf)])),
            ])),
            ("fmt", CBORFixture.text("apple-appattest")),
        ])

        // When fields arrive in a different order, identity still comes from the leaf.
        #expect(try AttestedDeviceKeyID.derive(from: data) == Fixture.attestedClientKeyID)
    }

    @Test("Missing, ambiguous or invalid certificate paths are rejected", arguments: 0..<10)
    func invalidCertificatePath(variant: Int) {
        let validChain = CBORFixture.array([CBORFixture.bytes(leaf)])
        let validStatement = CBORFixture.map([("x5c", validChain)])
        let format = ("fmt", CBORFixture.text("apple-appattest"))
        let invalid: Data
        switch variant {
        case 0: invalid = CBORFixture.map([("attStmt", validStatement)])
        case 1: invalid = CBORFixture.map([("fmt", CBORFixture.text("other")), ("attStmt", validStatement)])
        case 2: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.bytes(leaf))])
        case 3: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([]))])
        case 4: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([("x5c", CBORFixture.array([]))]))])
        case 5: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([("x5c", CBORFixture.array([CBORFixture.text("not DER")]))]))])
        case 6: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([("x5c", CBORFixture.bytes(leaf))]))])
        case 7: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([("x5c", CBORFixture.array([CBORFixture.bytes(Data([1, 2, 3]))]))]))])
        case 8: invalid = CBORFixture.map([format, format, ("attStmt", validStatement)])
        default: invalid = CBORFixture.map([format, ("attStmt", CBORFixture.map([("x5c", validChain), ("x5c", validChain)]))])
        }

        #expect(throws: (any Error).self) {
            try AttestedDeviceKeyID.derive(from: invalid)
        }
    }

    @Test("Excessive nesting is rejected before exhausting the call stack")
    func excessiveNesting() {
        let nested = Data(repeating: 0x81, count: 32) + Data([0x00])
        let data = CBORFixture.map([
            ("fmt", CBORFixture.text("apple-appattest")),
            ("attStmt", CBORFixture.map([("x5c", CBORFixture.array([CBORFixture.bytes(leaf)]))])),
            ("unused", nested),
        ])
        #expect(throws: (any Error).self) {
            try AttestedDeviceKeyID.derive(from: data)
        }
    }
}

private enum CBORFixture {
    static func text(_ value: String) -> Data { item(major: 3, bytes: Data(value.utf8)) }
    static func bytes(_ value: Data) -> Data { item(major: 2, bytes: value) }
    static func array(_ values: [Data]) -> Data {
        header(major: 4, count: values.count) + values.reduce(Data(), +)
    }
    static func map(_ values: [(String, Data)]) -> Data {
        header(major: 5, count: values.count) + values.reduce(Data()) { $0 + text($1.0) + $1.1 }
    }
    private static func item(major: UInt8, bytes: Data) -> Data {
        header(major: major, count: bytes.count) + bytes
    }
    private static func header(major: UInt8, count: Int) -> Data {
        if count < 24 { return Data([major << 5 | UInt8(count)]) }
        if count <= 255 { return Data([major << 5 | 24, UInt8(count)]) }
        return Data([major << 5 | 25, UInt8(count >> 8), UInt8(count & 255)])
    }
}
