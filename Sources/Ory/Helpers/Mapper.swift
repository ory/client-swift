/// A protocol that declares an interface used for transformation (or, map) from value of one type to another.
protocol Mapper {

    /// An input type.
    associatedtype Input

    /// An output type.
    associatedtype Output

    /// A definition of failure which could be  encountered during mapping.
    associatedtype Failure: Error

    /// Maps value of given type to another.
    ///
    /// - Parameter input: A value which is going to be mapped.
    /// - Returns: A result of map operation.
    static func map(_ input: Input) -> Result<Output, Failure>
}

extension Mapper {

    /// Maps optional value of given type to another.
    ///
    /// When input is `nil`, it returns successful mapping with `nil` as a result.
    ///
    /// - Parameter input: An optional value which is going to be mapped.
    /// - Returns: A result of map operation.
    static func map<I>(_ input: I) -> Result<Output?, Failure> where I: OptionalProtocol, I.Wrapped == Input {
        guard let input = try? input.unwrapped() else { return .success(nil) }
        let result = Self.map(input)
        switch result {
        case .success(let output):
            return .success(output)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// Maps value of given type to another.
    ///
    /// Throws `Failure` when mapping operation failed.
    ///
    /// - Parameter input: A value which is going to be mapped.
    /// - Returns: A value result of map operation.
    static func map(_ input: Input) throws -> Output { try map(input).get() }

    /// Maps optional value of given type to another.
    ///
    /// When input is `nil`, it returns successful mapping with `nil` as a result. Throws `Failure` when mapping operation failed.
    ///
    /// - Parameter input: An optional value which is going to be mapped.
    /// - Returns: A value result of map operation.
    public static func map<I>(_ input: I) throws -> Output? where I: OptionalProtocol, I.Wrapped == Input { try map(input).get() }
}

extension Mapper where Failure == Never {

    /// Maps value of given type to another.
    ///
    /// This operations assumes that map operation is non-failable.
    ///
    /// - Parameter input: A value which is going to be mapped.
    /// - Returns: A value result of map operation.
    static func flatMap(_ input: Input) -> Output { map(input).get() }

    /// Maps value of given type to another.
    ///
    /// This operations assumes that map operation is non-failable. When input is `nil`, it returns `nil` as well.
    ///
    /// - Parameter input: An optional value which is going to be mapped.
    /// - Returns: An optional value result of map operation.
    static func flatMap<I>(_ input: I) -> Output? where I: OptionalProtocol, I.Wrapped == Input { map(input).get() }
    
    /// Maps array of given type to another output array
    ///
    /// - Parameter input: An array which is going to be mapped.
    /// - Returns: An array result of map operation.
    static func flatMap(_ input: [Input]) -> [Output] {
        input.map { Self.flatMap($0) }
    }
}
