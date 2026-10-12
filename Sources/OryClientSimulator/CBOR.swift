#if targetEnvironment(simulator)

import Foundation

/// Minimal CBOR encoder for the fixed attestation and login-signature payloads. Supports
/// only the types those payloads need: text strings, byte strings, maps, and arrays.
enum CBOR: Sendable {
    case textString(String)
    case byteString(Data)
    case map([(CBOR, CBOR)])
    case array([CBOR])

    func encode() -> Data {
        var out = Data()
        encode(into: &out)
        return out
    }

    private func encode(into data: inout Data) {
        switch self {
        case .textString(let string):
            let utf8 = Array(string.utf8)
            writeHeader(majorType: 3, value: UInt64(utf8.count), into: &data)
            data.append(contentsOf: utf8)

        case .byteString(let bytes):
            writeHeader(majorType: 2, value: UInt64(bytes.count), into: &data)
            data.append(bytes)

        case .map(let pairs):
            writeHeader(majorType: 5, value: UInt64(pairs.count), into: &data)
            for (key, value) in pairs {
                key.encode(into: &data)
                value.encode(into: &data)
            }

        case .array(let items):
            writeHeader(majorType: 4, value: UInt64(items.count), into: &data)
            for item in items {
                item.encode(into: &data)
            }
        }
    }

    private func writeHeader(majorType: UInt8, value: UInt64, into data: inout Data) {
        let mt = majorType << 5
        if value < 24 {
            data.append(mt | UInt8(value))
        } else if value <= UInt8.max {
            data.append(mt | 24)
            data.append(UInt8(value))
        } else if value <= UInt16.max {
            data.append(mt | 25)
            var be = UInt16(value).bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
        } else if value <= UInt32.max {
            data.append(mt | 26)
            var be = UInt32(value).bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
        } else {
            data.append(mt | 27)
            var be = value.bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
        }
    }
}

#endif
