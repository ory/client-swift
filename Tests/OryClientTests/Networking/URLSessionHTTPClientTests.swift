import Foundation
import Testing
@testable import OryClient

@Suite("URLSessionHTTPClient")
struct URLSessionHTTPClientTests {

    // Ory's native (API-type) flows reject any request carrying a `Cookie` header
    // (error 4000001), so the transport must never store or send cookies. Otherwise
    // cookies set while creating a flow (e.g. Cloudflare's `__cf_bm`) would be replayed
    // on the submit request and break the flow.
    @Test("The default session neither stores nor sends cookies")
    func defaultSessionDisablesCookies() {
        // Given / When
        let session = URLSessionHTTPClient.makeSession(projectURL: URL(string: "https://example.ory")!)

        // Then
        #expect(session.configuration.httpShouldSetCookies == false)
        #expect(session.configuration.httpCookieAcceptPolicy == .never)
        #expect(session.configuration.httpCookieStorage == nil)
    }
}
