/// An abstraction for `Optional<Wrapped>`. Internal — used only by `Mapper`.
protocol OptionalProtocol: ExpressibleByNilLiteral {

    associatedtype Wrapped

    static var none: Self { get }

    /// Unwraps optional.
    /// - Returns: Unwrapped value.
    func unwrapped() throws -> Wrapped
}
