import Foundation
import Testing
@testable import OryClient

/// Serialized because the stub's routes and captured requests are process-wide state.
@Suite("Session token origin", .serialized)
struct SessionTokenOriginTests {

    private struct Probe: Decodable, Sendable, Equatable {
        let a: Int
    }

    private struct ProbeRequest: FrontendRequest {
        let url: URL
        let sessionToken: String?
        var method: HTTPMethod { .get }
        var target: RequestTarget { .url(url) }
        var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
        typealias Response = Probe
    }

    private let projectURL = URL(string: "https://example.ory")!

    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectStubProtocol.self]
        return URLSessionHTTPClient(
            baseURL: projectURL,
            urlSession: URLSessionHTTPClient.makeSession(projectURL: projectURL, configuration: configuration)
        )
    }

    private func expectRefused(_ operation: () async throws -> Void) async {
        await #expect {
            try await operation()
        } throws: { error in
            guard case OryClientError.unexpectedResponse = error else { return false }
            return true
        }
    }

    @Test("A session token is never sent to another host")
    func refusesOtherHost() async {
        // Given
        RedirectStubProtocol.reset()
        let client = makeClient()

        // When / Then
        await expectRefused {
            _ = try await client.send(ProbeRequest(url: URL(string: "https://elsewhere.example/x")!, sessionToken: "real"))
        }
        #expect(RedirectStubProtocol.requests.isEmpty)
    }

    @Test("A session token is never sent to another scheme or port on the project host")
    func refusesOtherSchemeOrPort() async {
        // Given
        RedirectStubProtocol.reset()
        let client = makeClient()

        // When / Then
        await expectRefused {
            _ = try await client.send(ProbeRequest(url: URL(string: "http://example.ory/x")!, sessionToken: "real"))
        }
        await expectRefused {
            _ = try await client.send(ProbeRequest(url: URL(string: "https://example.ory:8443/x")!, sessionToken: "real"))
        }
        #expect(RedirectStubProtocol.requests.isEmpty)
    }

    @Test("The project origin matches with an explicit default port and different host casing")
    func acceptsEquivalentProjectOrigin() async throws {
        // Given
        RedirectStubProtocol.reset()
        let client = makeClient()

        // When
        _ = try await client.send(ProbeRequest(url: URL(string: "https://EXAMPLE.ory:443/x")!, sessionToken: "real"))

        // Then
        #expect(RedirectStubProtocol.requests.first?.value(forHTTPHeaderField: "X-Session-Token") == "real")
    }

    @Test("A request without a session token may target another origin")
    func allowsUnauthenticatedOtherOrigin() async throws {
        // Given
        RedirectStubProtocol.reset()
        let client = makeClient()

        // When
        _ = try await client.send(ProbeRequest(url: URL(string: "https://elsewhere.example/x")!, sessionToken: nil))

        // Then
        #expect(RedirectStubProtocol.requests.count == 1)
    }

    @Test("A redirect to another origin is followed without the session token")
    func dropsTokenOnCrossOriginRedirect() async throws {
        // Given the project answers with a redirect to another origin
        RedirectStubProtocol.reset(redirects: ["https://example.ory/start": "https://elsewhere.example/landing"])
        let client = makeClient()

        // When
        _ = try await client.send(ProbeRequest(url: URL(string: "https://example.ory/start")!, sessionToken: "real"))

        // Then
        let requests = RedirectStubProtocol.requests
        #expect(requests.map(\.url?.host) == ["example.ory", "elsewhere.example"])
        #expect(requests.first?.value(forHTTPHeaderField: "X-Session-Token") == "real")
        #expect(requests.last?.value(forHTTPHeaderField: "X-Session-Token") == nil)
    }

    @Test("A redirect within the project origin keeps the session token")
    func keepsTokenOnSameOriginRedirect() async throws {
        // Given
        RedirectStubProtocol.reset(redirects: ["https://example.ory/start": "https://example.ory/landing"])
        let client = makeClient()

        // When
        _ = try await client.send(ProbeRequest(url: URL(string: "https://example.ory/start")!, sessionToken: "real"))

        // Then
        let requests = RedirectStubProtocol.requests
        #expect(requests.map(\.url?.path) == ["/start", "/landing"])
        #expect(requests.last?.value(forHTTPHeaderField: "X-Session-Token") == "real")
    }

    @Test("The legacy data-task transport also drops the token on a cross-origin redirect")
    func legacyTransportDropsTokenOnCrossOriginRedirect() async throws {
        // Given
        RedirectStubProtocol.reset(redirects: ["https://example.ory/start": "https://elsewhere.example/landing"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectStubProtocol.self]
        let client = URLSessionHTTPClient(
            baseURL: projectURL,
            urlSession: URLSessionHTTPClient.makeSession(projectURL: projectURL, configuration: configuration),
            transport: .legacyDataTask
        )

        // When
        _ = try await client.send(ProbeRequest(url: URL(string: "https://example.ory/start")!, sessionToken: "real"))

        // Then
        #expect(RedirectStubProtocol.requests.last?.url?.host == "elsewhere.example")
        #expect(RedirectStubProtocol.requests.last?.value(forHTTPHeaderField: "X-Session-Token") == nil)
    }

    @Test("The default session keeps the redirect guard and the cookie hardening")
    func defaultSessionConfiguration() {
        // Given / When
        let session = URLSessionHTTPClient.makeSession(projectURL: projectURL)

        // Then
        #expect(session.delegate is SessionTokenRedirectGuard)
        #expect(session.configuration.httpShouldSetCookies == false)
        #expect(session.configuration.httpCookieStorage == nil)
    }
}

/// Answers each request with `{"a":1}`, or with a `302` for URLs listed in `redirects`.
/// The redirected request carries every header of the original, as URLSession builds it,
/// so the session delegate is what decides whether the token survives.
final class RedirectStubProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private nonisolated(unsafe) static var redirects: [String: String] = [:]
    private nonisolated(unsafe) static var captured: [URLRequest] = []

    static func reset(redirects: [String: String] = [:]) {
        lock.withLock {
            Self.redirects = redirects
            Self.captured = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let target = Self.lock.withLock { () -> String? in
            Self.captured.append(request)
            return Self.redirects[url.absoluteString]
        }
        if let target, let targetURL = URL(string: target) {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": target]
            )!
            var redirected = request
            redirected.url = targetURL
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"a":1}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
