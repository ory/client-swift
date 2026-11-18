import Foundation
import Testing
@testable import Ory

@Suite("Keychain project scope")
struct KeychainProjectScopeTests {

    private func service(_ url: String) -> String {
        KeychainProjectScope.service(for: URL(string: url)!)
    }

    @Test("different projects get different services", arguments: [
        ("https://alpha.projects.oryapis.com", "https://beta.projects.oryapis.com"),
        ("https://auth.acme.com/tenant-a", "https://auth.acme.com/tenant-b"),
        ("https://auth.acme.com", "https://auth.acme.com:8443"),
        ("http://auth.acme.com", "https://auth.acme.com"),
        ("https://auth.acme.com/tenant%2Fa", "https://auth.acme.com/tenant/a"),
    ])
    func differentProjects(first: String, second: String) {
        // Given two project URLs that address different deployments
        // When / Then
        #expect(service(first) != service(second))
    }

    @Test("spellings of the same project URL share one service", arguments: [
        "https://Auth.Acme.com/kratos/",
        "HTTPS://auth.acme.com/kratos",
        "https://auth.acme.com/kratos?flow=1#top",
        "https://user:secret@auth.acme.com/kratos",
    ])
    func sameProject(spelling: String) {
        // Given a project URL that differs only in case, a trailing slash, query, fragment or credentials
        // When / Then
        #expect(service(spelling) == service("https://auth.acme.com/kratos"))
    }

    @Test("the service is readable in the Keychain")
    func readableService() {
        #expect(service("https://auth.acme.com:8443/kratos") == "com.ory.client:https://auth.acme.com:8443/kratos")
    }

    @Test("the configuration's default stores are scoped to its project URL")
    func configurationDefaults() throws {
        // Given
        let alpha = URL(string: "https://alpha.projects.oryapis.com")!
        let beta = URL(string: "https://beta.projects.oryapis.com")!

        // When
        let alphaConfiguration = OryClientConfiguration(projectURL: alpha)
        let betaConfiguration = OryClientConfiguration(projectURL: beta)

        // Then
        let alphaSession = try #require(alphaConfiguration.sessionStorage as? OryKeychainSessionStorage)
        let betaSession = try #require(betaConfiguration.sessionStorage as? OryKeychainSessionStorage)
        let alphaKeys = try #require(alphaConfiguration.deviceKeyStore as? OryKeychainDeviceKeyStore)
        let betaKeys = try #require(betaConfiguration.deviceKeyStore as? OryKeychainDeviceKeyStore)

        #expect(alphaSession.service == KeychainProjectScope.service(for: alpha))
        #expect(alphaKeys.service == KeychainProjectScope.service(for: alpha))
        #expect(alphaSession.service != betaSession.service)
        #expect(alphaKeys.service != betaKeys.service)
        #expect(alphaKeys.deviceOperationScope != betaKeys.deviceOperationScope)
    }
}
