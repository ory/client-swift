import Foundation

// MARK: - ValidationRule String Atomics

extension ValidationRule where Input == String {

    public static func hasNotSequentialDigits(error: Error, minFailingLength: Int? = nil) -> ValidationRule {
        ValidationRule(
            predicate: {
                let digits = $0.compactMap { Int(String($0)) }
                let minFailingLength = minFailingLength ?? digits.count

                guard digits.count >= 2 else { return .valid }

                var ascendingCount = 0
                var descendingCount = 0

                for i in 1..<digits.count {
                    let previousDigit = digits[i - 1]
                    let currentDigit = digits[i]
                    if previousDigit + 1 == currentDigit {
                        ascendingCount += 1
                    } else {
                        ascendingCount = 0
                    }

                    if previousDigit - 1 == currentDigit {
                        descendingCount += 1
                    } else {
                        descendingCount = 0
                    }

                    if ascendingCount == minFailingLength - 1 || descendingCount == minFailingLength - 1 {
                        return .invalid([error])
                    }
                }

                return .valid
            },
            error: error
        )
    }

    public static func hasNotConsecutiveCharacters(
        error: Error,
        minFailingLength: Int? = nil,
        ignoreCasing: Bool = false
    ) -> ValidationRule {
        ValidationRule(
            predicate: {
                var textToValidate = $0
                if ignoreCasing {
                    textToValidate = textToValidate.lowercased()
                }
                let characters = Array(textToValidate)
                let minFailingLength = minFailingLength ?? characters.count

                guard characters.count >= 2 else { return .valid }

                var sequenceLength = 0

                for i in 1..<characters.count {
                    let previousChar = characters[i - 1]
                    let currentChar = characters[i]
                    if currentChar == previousChar {
                        sequenceLength += 1
                    } else {
                        sequenceLength = 0
                    }

                    if sequenceLength == minFailingLength - 1 {
                        return .invalid([error])
                    }
                }

                return ValidationResult.valid
            },
            error: error
        )
    }
}

// MARK: - ValidationRule String Molecules

extension ValidationRule where Input == String {

    public static func hasNotSequentialDigits(minFailingLength: Int? = nil) -> ValidationRule {
        hasNotSequentialDigits(
            error: StringValidationError.containSequentialNumbers,
            minFailingLength: minFailingLength
        )
    }

    public static func hasNotConsecutiveCharacters(minFailingLength: Int? = nil, ignoreCasing: Bool = false) -> ValidationRule {
        hasNotConsecutiveCharacters(
            error: StringValidationError.containConsecutiveCharacters,
            minFailingLength: minFailingLength,
            ignoreCasing: ignoreCasing
        )
    }
}
