public protocol ValidationCommand {

    associatedtype PreviousCommand: ValidationCommand
    associatedtype Output

    var accumulatedResult: ValidationResult { get }
    var chainResult: ValidationChainResult<Output> { get }
}

extension ValidationCommand {

    public var accumulatedResult: ValidationResult {
        switch chainResult {
        case .break(let errors):
            return errors.isEmpty ? .valid : .invalid(errors)

        case .next(_, let errors):
            return errors.isEmpty ? .valid : .invalid(errors)
        }
    }
}

extension ValidationCommand {

    public func match(rule: ValidationRule<Self.Output>) -> Match<Self> {
        Match(previous: self, rule: rule)
    }
}
