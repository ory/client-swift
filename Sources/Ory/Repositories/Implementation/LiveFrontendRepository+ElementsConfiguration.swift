import Foundation

extension LiveFrontendRepository {

    func elementsConfiguration() async throws -> OryElementsConfiguration {
        let response = try await gateway.send(ElementsConfigurationRequest())
        return ElementsConfigurationMapper.flatMap(try gateway.decoded(response))
    }
}
