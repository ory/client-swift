import Foundation

// MARK: - ValidationRule Collection Atomics

extension ValidationRule where Input: Collection {
    
    public static func hasNumberOfElements(equalTo value: Int, error: Error) -> ValidationRule<Input> {
        ValidationRule(
            predicate: { $0.count == value ? .valid : .invalid([error]) },
            error: error
        )
    }
    
    public static func hasNumberOfElements(in range: ClosedRange<UInt>, error: Error) -> ValidationRule<Input> {
        ValidationRule(
            predicate: { range.contains(UInt($0.count)) ? .valid : .invalid([error]) },
            error: error
        )
    }
    
    public static func hasNumberOfElements(in range: PartialRangeFrom<UInt>, error: Error) -> ValidationRule<Input> {
        ValidationRule(
            predicate: { range.contains(UInt($0.count)) ? .valid : .invalid([error]) },
            error: error
        )
    }
    
    public static func hasNumberOfElements(in range: PartialRangeUpTo<UInt>, error: Error) -> ValidationRule<Input> {
        ValidationRule(
            predicate: { range.contains(UInt($0.count)) ? .valid : .invalid([error]) },
            error: error
        )
    }

    public static func hasNumberOfElements(in range: Range<UInt>, error: Error) -> ValidationRule<Input> {
        ValidationRule(
            predicate: { range.contains(UInt($0.count)) ? .valid : .invalid([error]) },
            error: error
        )
    }
}

// MARK: - ValidationRule Collection Molecules

extension ValidationRule where Input: Collection {
    
    public static func isEmpty() -> ValidationRule<Input> {
        isEmpty(error: ValidationError.generic)
    }

    public static func isEmpty(error: Error) -> ValidationRule<Input> {
        hasNumberOfElements(in: 0..<1, error: error)
    }

    public static func isNotEmpty() -> ValidationRule<Input> {
        isNotEmpty(error: ValidationError.generic)
    }

    public static func isNotEmpty(error: Error) -> ValidationRule<Input> {
        hasNumberOfElements(in: 1..., error: error)
    }
    
    public static func hasNumberOfElements(equalTo value: Int) -> ValidationRule<Input> {
        hasNumberOfElements(equalTo: value, error: ValidationError.generic)
    }
    
    public static func hasNumberOfElements(in range: ClosedRange<UInt>) -> ValidationRule<Input> {
        hasNumberOfElements(in: range, error: ValidationError.generic)
    }
    
    public static func hasNumberOfElements(in range: PartialRangeFrom<UInt>) -> ValidationRule<Input> {
        hasNumberOfElements(in: range, error: ValidationError.generic)
    }
    
    public static func hasNumberOfElements(in range: PartialRangeUpTo<UInt>) -> ValidationRule<Input> {
        hasNumberOfElements(in: range, error: ValidationError.generic)
    }
   
    public static func hasNumberOfElements(in range: Range<UInt>) -> ValidationRule<Input> {
        hasNumberOfElements(in: range, error: ValidationError.generic)
    }
}
