import Foundation
import Testing
@testable import OryClient

@Suite("FrontendRequestResolver")
struct FrontendRequestResolverTests {

    private let base = URL(string: "https://example.com")!

    @Test("A relative path resolves against the base URL and carries the session token")
    func resolvesPathAndToken() throws {
        // Given / When
        let resolved = try FrontendRequestResolver.resolve(WhoamiRequest(sessionToken: "tok"), baseURL: base)

        // Then
        #expect(resolved.method == .get)
        #expect(resolved.url.absoluteString == "https://example.com/sessions/whoami")
        #expect(resolved.sessionToken == "tok")
        #expect(resolved.body == nil)
    }

    @Test("A trailing slash on the base URL does not double up in the path")
    func normalizesTrailingSlash() throws {
        let resolved = try FrontendRequestResolver.resolve(
            WhoamiRequest(sessionToken: "tok"),
            baseURL: URL(string: "https://example.com/")!
        )
        #expect(resolved.url.absoluteString == "https://example.com/sessions/whoami")
    }

    @Test("Query items are appended to the path")
    func appendsQuery() throws {
        let resolved = try FrontendRequestResolver.resolve(GetVerificationFlowRequest(id: "v-9"), baseURL: base)
        #expect(resolved.url.absoluteString == "https://example.com/self-service/verification/flows?id=v-9")
    }

    @Test("An absolute target URL is used verbatim, and a nil session token stays nil")
    func usesAbsoluteURL() throws {
        let action = URL(string: "https://example.com/self-service/login?flow=x")!
        let resolved = try FrontendRequestResolver.resolve(
            SubmitLoginRequest(actionURL: action, fields: ["method": "password"], sessionToken: nil),
            baseURL: base
        )

        #expect(resolved.method == .post)
        #expect(resolved.url == action)
        #expect(resolved.sessionToken == nil)

        // And the body is the JSON-encoded fields.
        let decoded = try JSONDecoder().decode([String: String].self, from: #require(resolved.body))
        #expect(decoded == ["method": "password"])
    }
}
