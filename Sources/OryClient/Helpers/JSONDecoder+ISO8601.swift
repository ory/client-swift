import Foundation

extension JSONDecoder {

    /// A pre-configured `JSONDecoder` with ISO 8601 date decoding strategy.
    ///
    /// Used as the default decoder for Ory Kratos API responses which
    /// encode dates in ISO 8601 format.
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
