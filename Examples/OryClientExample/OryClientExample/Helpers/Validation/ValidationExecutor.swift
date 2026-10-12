public protocol ValidationExecutor {

    associatedtype Output

    func execute() -> Output
}
