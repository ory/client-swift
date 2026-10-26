import Foundation
import Testing
@testable import OryClient

@Suite("Client identification header")
struct ClientIdentificationTests {

    private let projectURL = URL(string: "https://example.ory")!

    private func resolved(sessionToken: String? = nil) -> ResolvedHTTPRequest {
        ResolvedHTTPRequest(method: .get, url: projectURL.appendingPathComponent("probe"), body: nil, sessionToken: sessionToken)
    }

    @Test("The client version is a semantic version")
    func versionIsSemantic() {
        // Given / When
        let components = ClientIdentification.version.split(separator: ".", omittingEmptySubsequences: false)

        // Then
        #expect(components.count == 3)
        #expect(components.allSatisfy { !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } })
    }

    @Test("The header value names the Swift client, its version, and the running OS")
    func headerValueFormat() {
        // Given
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let osName = "iOS"
        #else
        let osName = "macOS"
        #endif

        // When
        let value = ClientIdentification.headerValue

        // Then
        #expect(value == "ory-client-swift/\(ClientIdentification.version) (\(osName) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion))")
    }

    @Test("Every request carries the Ory-Client header, visible to the observer")
    func everyRequestCarriesHeader() async throws {
        // Given
        let client = URLSessionHTTPClient(baseURL: projectURL)

        // When
        let (urlRequest, outgoing, event) = try await client.makeURLRequest(resolved(sessionToken: "token"))

        // Then
        #expect(urlRequest.value(forHTTPHeaderField: "Ory-Client") == ClientIdentification.headerValue)
        #expect(outgoing.headers["Ory-Client"] == ClientIdentification.headerValue)
        #expect(event.headers["Ory-Client"] == ClientIdentification.headerValue)
    }
}
