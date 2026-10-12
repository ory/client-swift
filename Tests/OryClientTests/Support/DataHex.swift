import Foundation

extension Data {
    /// Builds bytes from a hex string; test-vector literal support only.
    init(hex: String) {
        let characters = Array(hex.filter(\.isHexDigit))
        precondition(characters.count.isMultiple(of: 2), "Hex literal must have an even number of digits")
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            bytes.append(UInt8(String(characters[index...index + 1]), radix: 16)!)
        }
        self.init(bytes)
    }
}
