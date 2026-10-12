public enum ValidationResult {
    case invalid([Error])
    case valid
}

extension ValidationResult {

    public var isValid: Bool {
        switch self {
        case .invalid: return false
        case .valid: return true
        }
    }
}
