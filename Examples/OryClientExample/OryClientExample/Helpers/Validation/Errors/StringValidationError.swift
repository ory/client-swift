import Foundation

public enum StringValidationError: Error {
    case containSequentialNumbers
    case containConsecutiveCharacters
}

extension StringValidationError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .containSequentialNumbers:
            return "Sequential numbers are not allowed."
        case .containConsecutiveCharacters:
            return "Consecutive characters are not allowed."
        }
    }
}
