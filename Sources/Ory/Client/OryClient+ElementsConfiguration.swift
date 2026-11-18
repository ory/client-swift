import Foundation

extension OryClient: OryElementsConfigurationLoading {

    public func elementsConfiguration() async throws -> OryElementsConfiguration {
        try await elements.elementsConfiguration()
    }
}
