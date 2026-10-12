import FlowStacks

public struct RouterPath<Element> where Element: Hashable & Sendable {

    var flowPath: FlowPath

    public init(_ routes: [Route<AnyHashable>] = []) {
        self.flowPath = .init(routes)
    }
}
