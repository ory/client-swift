import FlowStacks
import SwiftUI

public struct Router<Root, Page, Destination>: View where Destination: View, Page: Hashable & Sendable, Root: View {

    @Binding private var path: RouterPath<Page>
    @ViewBuilder private var root: () -> Root
    @ViewBuilder private var destination: (Binding<Page>) -> Destination

    private var withNavigation: Bool

    public init(
        _ path: Binding<RouterPath<Page>>,
        withNavigation: Bool = false,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Binding<Page>) -> Destination
    ) {
        _path = path
        self.withNavigation = withNavigation
        self.root = root
        self.destination = destination
    }

    public init(
        _ path: Binding<RouterPath<Page>>,
        withNavigation: Bool = false,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Page) -> Destination
    ) {
        _path = path
        self.withNavigation = withNavigation
        self.root = root
        self.destination = { binding in destination(binding.wrappedValue) }
    }

    public var body: some View {
        FlowStack(
            $path.flowPath,
            withNavigation: withNavigation,
            root: {
                root()
                    .flowDestination(for: Page.self) { page in
                        destination(page)
                    }
            }
        )
    }
}
