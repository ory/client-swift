import Foundation

extension ValidationResult {

    /// The first validation error's user-facing message, or `nil` when the result is valid.
    /// Convenient for surfacing a single message in the UI.
    var firstErrorMessage: String? {
        switch self {
        case .valid:
            return nil
        case let .invalid(errors):
            return errors.first?.localizedDescription
        }
    }
}
