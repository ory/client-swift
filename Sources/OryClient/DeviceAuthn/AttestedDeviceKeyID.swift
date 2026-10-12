import CryptoKit
import Foundation
import Security

/// Extracts the P-256 signing key's identity; the backend remains responsible for
/// verifying the attestation chain, nonce, App ID and authenticator data.
enum AttestedDeviceKeyID {

    enum ExtractionError: Error, Sendable {
        case malformedAttestation
        case unsupportedPublicKey
    }

    static func derive(from attestation: Data) throws -> String {
        var decoder = AttestationCBORDecoder(bytes: Array(attestation))
        let value = try decoder.read()
        guard decoder.isAtEnd,
              case .map(let root) = value,
              case .text("apple-appattest") = root["fmt"],
              case .map(let statement) = root["attStmt"],
              case .array(let certificates) = statement["x5c"],
              case .bytes(let leaf) = certificates.first,
              let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
              let key = SecCertificateCopyKey(certificate),
              let point = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw ExtractionError.malformedAttestation
        }
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: point) else {
            throw ExtractionError.unsupportedPublicKey
        }
        // Go hashes x509.MarshalPKIXPublicKey, not Apple's key ID (SHA256 of X9.63).
        return SHA256.hash(data: publicKey.derRepresentation)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Definite-length CBOR used by App Attest. Reads the whole value to reject ambiguous
/// duplicate keys and truncated containers, including fields not used for correlation.
private struct AttestationCBORDecoder {

    indirect enum Value {
        case map([String: Value])
        case array([Value])
        case bytes(Data)
        case text(String)
        case other
    }

    let bytes: [UInt8]
    private var offset = 0
    var isAtEnd: Bool { offset == bytes.count }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func read(depth: Int = 0) throws -> Value {
        guard depth < 16 else { throw invalid() }
        let header = try byte()
        let argument = try argument(header & 0x1f)
        switch header >> 5 {
        case 0, 1, 7:
            return .other
        case 2, 3:
            let count = try boundedCount(argument)
            let content = bytes[offset..<(offset + count)]
            offset += count
            if header >> 5 == 2 { return .bytes(Data(content)) }
            guard let text = String(bytes: content, encoding: .utf8) else { throw invalid() }
            return .text(text)
        case 4:
            let count = try boundedCount(argument)
            var values: [Value] = []
            for _ in 0..<count {
                values.append(try read(depth: depth + 1))
            }
            return .array(values)
        case 5:
            let count = try boundedCount(argument)
            guard count <= (bytes.count - offset) / 2 else { throw invalid() }
            var values: [String: Value] = [:]
            for _ in 0..<count {
                guard case .text(let key) = try read(depth: depth + 1), values[key] == nil else {
                    throw invalid()
                }
                values[key] = try read(depth: depth + 1)
            }
            return .map(values)
        case 6:
            _ = try read(depth: depth + 1)
            return .other
        default:
            throw invalid()
        }
    }

    private mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw invalid() }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func argument(_ additional: UInt8) throws -> UInt64 {
        if additional < 24 { return UInt64(additional) }
        guard additional <= 27 else { throw invalid() }
        let count = 1 << Int(additional - 24)
        var value: UInt64 = 0
        for _ in 0..<count {
            value = (value << 8) | UInt64(try byte())
        }
        return value
    }

    private func boundedCount(_ value: UInt64) throws -> Int {
        guard value <= UInt64(bytes.count - offset) else { throw invalid() }
        return Int(value)
    }

    private func invalid() -> AttestedDeviceKeyID.ExtractionError { .malformedAttestation }
}
