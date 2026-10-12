public struct Match<PreviousCommand>: ValidationCommand where PreviousCommand: ValidationCommand {

    public typealias Output = PreviousCommand.Output

    public let chainResult: ValidationChainResult<Output>

    let previous: PreviousCommand
    let rule: ValidationRule<PreviousCommand.Output>

    public init(
        previous: PreviousCommand,
        rule: ValidationRule<PreviousCommand.Output>
    ) {
        self.chainResult = Self.validate(previous: previous, rule: rule)
        self.previous = previous
        self.rule = rule
    }

    private static func validate(
        previous: PreviousCommand,
        rule: ValidationRule<PreviousCommand.Output>
    ) -> ValidationChainResult<PreviousCommand.Output> {
        let previousChainResult = previous.chainResult
        switch previousChainResult {
        case let .break(previousErrors):
            return .break(errors: previousErrors)

        case let .next(input, previousErrors):
            let result = rule.predicate(input)
            switch result {
            case .invalid(let errors):
                var modifiedErrors = previousErrors
                modifiedErrors.append(contentsOf: errors)
                return .next(output: input, errors: modifiedErrors)

            case .valid:
                return .next(output: input, errors: previousErrors)
            }
        }
    }
}
