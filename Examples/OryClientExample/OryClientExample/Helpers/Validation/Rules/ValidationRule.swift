public struct ValidationRule<Input> {

    public typealias Predicate = (_ value: Input) -> ValidationResult

    let error: Error
    let predicate: Predicate

    public init(predicate: @escaping Predicate, error: Error) {
        self.error = error
        self.predicate = predicate
    }
}
