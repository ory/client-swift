import Foundation

/// Errors surfaced by ``PINValidator`` when a chosen PIN does not meet this app's policy.
///
/// The policy lives entirely in the client: `OryClient` never validates PIN format (the server
/// never sees the PIN), so the integrating app defines and enforces its own rules.
enum PINValidationError: Error, LocalizedError {
    case invalidLength
    case allSameCharacters

    var errorDescription: String? {
        switch self {
        case .invalidLength:
            return "PIN must be between \(PINValidator.minLength) and \(PINValidator.maxLength) digits."
        case .allSameCharacters:
            return "PIN can't be all the same digit (like 0000)."
        }
    }
}
