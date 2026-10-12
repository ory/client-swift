import FlowStacks
import SwiftUI

@MainActor
public protocol CoordinatorProtocol: ObservableObject {
    
    associatedtype Page: Hashable & Sendable
    
    var path: RouterPath<Self.Page> { get set }

    func dismiss()
    func push(_ page: Page)
    func presentSheet(_ page: Page, withNavigation: Bool)
    func presentCover(_ page: Page, withNavigation: Bool)
    func pop()
    func popToRoot()
}

extension CoordinatorProtocol {
    
    public func dismiss() {
        path.flowPath.dismiss()
    }
    
    public func push(_ page: Page) {
        path.flowPath.push(page)
    }
    
    public func presentSheet(_ page: Page, withNavigation: Bool) {
        path.flowPath.presentSheet(page, withNavigation: withNavigation)
    }
    
    public func presentCover(_ page: Page, withNavigation: Bool) {
        path.flowPath.presentCover(page, withNavigation: withNavigation)
    }
    
    public func pop() {
        path.flowPath.pop()
    }
    
    public func popToRoot() {
        path.flowPath.popToRoot()
    }
}
