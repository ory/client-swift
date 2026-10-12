public struct Validation<Input>: ValidationCommand {

    public typealias PreviousCommand = Self
    public typealias Output = Input

    public let accumulatedResult = ValidationResult.valid
    public let chainResult: ValidationChainResult<Output>

    public init(input: Input) {
        self.chainResult = .next(output: input, errors: [])
    }
}
