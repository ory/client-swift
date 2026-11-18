import Foundation

/// Reads the project's Ory Elements configuration (the `/elements/configuration` endpoint).
protocol ElementsConfigurationRepository: Sendable {
    func elementsConfiguration() async throws -> OryElementsConfiguration
}
