import Foundation
import Testing
@testable import OryClient

@Suite("Interceptors", .serialized)
struct InterceptorTests {

    private struct Probe: Decodable, Sendable, Equatable {
        let a: Int
    }

    private struct ProbeRequest: FrontendRequest {
        let sessionToken: String?
        var method: HTTPMethod { .get }
        var target: RequestTarget { .path("/probe") }
        var authorization: RequestAuthorization { sessionToken.map(RequestAuthorization.sessionToken) ?? .none }
        typealias Response = Probe
    }

    private struct HeaderSetter: OryRequestInterceptor {
        let headers: [String: String]
        func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest {
            var request = request
            for (name, value) in headers {
                request.headers[name] = value
            }
            return request
        }
    }

    private struct NativeLogin: Decodable, Sendable {
        let sessionToken: String

        enum CodingKeys: String, CodingKey {
            case sessionToken = "session_token"
        }
    }

    private struct NativeLoginRequest: FrontendRequest {
        var method: HTTPMethod { .post }
        var target: RequestTarget { .path("/self-service/login") }
        var body: (any Encodable & Sendable)? { ["identifier": "alice@example.com", "password": "hunter2", "method": "password"] }
        typealias Response = NativeLogin
    }

    private struct DeviceLoginRequest: FrontendRequest {
        var method: HTTPMethod { .post }
        var target: RequestTarget { .path("/self-service/login") }
        var body: (any Encodable & Sendable)? { ["method": "deviceauthn", "client_key_id": "key-1", "signature": "assertion"] }
        typealias Response = NativeLogin
    }

    private actor RequestCapture: OryRequestInterceptor {
        private(set) var seenBody: Data?
        func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest {
            seenBody = request.body
            return request
        }
    }

    private actor ResponseCapture: OryResponseInterceptor {
        private(set) var seenTokenValue: String?
        private(set) var seenBody: Data?
        func intercept(_ response: OryReceivedResponse) async throws {
            seenTokenValue = response.request.headers["X-Session-Token"]
            seenBody = response.body
        }
    }

    private struct ThrowingResponseInterceptor: OryResponseInterceptor {
        func intercept(_ response: OryReceivedResponse) async throws {
            throw TestError.boom
        }
    }

    private static func json(_ data: Data?) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: try #require(data))
    }

    private enum TestError: Error { case boom }

    private func makeClient(
        request: [any OryRequestInterceptor] = [],
        response: [any OryResponseInterceptor] = [],
        observer: (any OryNetworkObserver)? = nil
    ) -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InterceptorStubProtocol.self]
        return URLSessionHTTPClient(
            baseURL: URL(string: "https://example.ory")!,
            urlSession: URLSession(configuration: configuration),
            requestInterceptors: request,
            responseInterceptors: response,
            observer: observer
        )
    }

    @Test("Request interceptors run in order, mutate headers, and cannot overwrite the session token (even under a different-cased name)")
    func requestChain() async throws {
        // Given two interceptors, the second setting a header the first also set (order), and
        // trying to clobber the session token both same-cased and differently-cased.
        InterceptorStubProtocol.configure(body: Data(#"{"a":1}"#.utf8))
        let client = makeClient(request: [
            HeaderSetter(headers: ["X-Order": "first", "X-A": "1"]),
            HeaderSetter(headers: [
                "X-Order": "second", "X-B": "2",
                "X-Session-Token": "evil", "x-session-token": "evil-lowercase",
            ]),
        ])

        // When
        _ = try await client.send(ProbeRequest(sessionToken: "real"))

        // Then both ran, the second won the shared header, and the real token survived — the
        // client applies it directly on the URLRequest after the header loop, and HTTP header
        // names are case-insensitive, so neither clobber attempt wins.
        let sent = InterceptorStubProtocol.lastRequest
        #expect(sent?.value(forHTTPHeaderField: "X-A") == "1")
        #expect(sent?.value(forHTTPHeaderField: "X-B") == "2")
        #expect(sent?.value(forHTTPHeaderField: "X-Order") == "second")
        #expect(sent?.value(forHTTPHeaderField: "X-Session-Token") == "real")
    }

    @Test("Response interceptors never receive the session token")
    func responseInterceptorNeverSeesToken() async throws {
        // Given a response interceptor that captures the request's headers
        InterceptorStubProtocol.configure(body: Data(#"{"a":1}"#.utf8))
        let capture = ResponseCapture()
        let client = makeClient(response: [capture])

        // When a request is sent with a session token
        _ = try await client.send(ProbeRequest(sessionToken: "real"))

        // Then the token was sent on the wire but never exposed to the response interceptor
        #expect(InterceptorStubProtocol.lastRequest?.value(forHTTPHeaderField: "X-Session-Token") == "real")
        #expect(await capture.seenTokenValue == nil)
    }

    @Test("OryHeaderInterceptor adds its headers")
    func headerInterceptor() async throws {
        InterceptorStubProtocol.configure(body: Data(#"{"a":1}"#.utf8))
        let client = makeClient(request: [OryHeaderInterceptor { _ in ["X-H": "v"] }])

        _ = try await client.send(ProbeRequest(sessionToken: nil))

        #expect(InterceptorStubProtocol.lastRequest?.value(forHTTPHeaderField: "X-H") == "v")
    }

    @Test("Request interceptors see credentials redacted while the original body is sent")
    func requestInterceptorSeesRedactedBody() async throws {
        // Given a request interceptor that captures the body it is shown
        let capture = RequestCapture()
        let client = makeClient(request: [capture])
        let resolved = try FrontendRequestResolver.resolve(NativeLoginRequest(), baseURL: URL(string: "https://example.ory")!)

        // When the client builds a password login request
        let (urlRequest, outgoing, _) = try await client.makeURLRequest(resolved)

        // Then the interceptor and the outgoing copy see the password redacted, other fields intact
        let seen = try Self.json(await capture.seenBody)
        #expect(seen["password"] == CredentialRedaction.placeholder)
        #expect(seen["identifier"] == "alice@example.com")
        #expect(seen["method"] == "password")
        #expect(try Self.json(outgoing.body)["password"] == CredentialRedaction.placeholder)

        // And the request on the wire carries the real password
        #expect(try Self.json(urlRequest.httpBody)["password"] == "hunter2")
    }

    @Test("Request interceptors see a device login assertion redacted while the original is sent")
    func requestInterceptorSeesRedactedDeviceSignature() async throws {
        // Given a request interceptor that captures the body it is shown
        let capture = RequestCapture()
        let client = makeClient(request: [capture])
        let resolved = try FrontendRequestResolver.resolve(DeviceLoginRequest(), baseURL: URL(string: "https://example.ory")!)

        // When the client builds a device login request
        let (urlRequest, outgoing, _) = try await client.makeURLRequest(resolved)

        // Then the interceptor and the outgoing copy see the assertion redacted
        let seen = try Self.json(await capture.seenBody)
        #expect(seen["signature"] == CredentialRedaction.placeholder)
        #expect(seen["client_key_id"] == "key-1")
        #expect(try Self.json(outgoing.body)["signature"] == CredentialRedaction.placeholder)

        // And the request on the wire carries the real assertion
        #expect(try Self.json(urlRequest.httpBody)["signature"] == "assertion")
    }

    @Test("Response interceptors see the session token redacted while the client decodes the original")
    func responseInterceptorSeesRedactedSessionToken() async throws {
        // Given a native login response carrying a session token
        InterceptorStubProtocol.configure(body: Data(#"{"session_token":"ory_st_real"}"#.utf8))
        let capture = ResponseCapture()
        let client = makeClient(response: [capture])

        // When the client receives it
        let response = try await client.send(NativeLoginRequest())

        // Then the interceptor saw a placeholder and the client decoded the real token
        #expect(try Self.json(await capture.seenBody)["session_token"] == CredentialRedaction.placeholder)
        #expect(try response.success().sessionToken == "ory_st_real")
    }

    @Test("A response interceptor that throws fails as unexpectedResponse, and the observer sees a receive but no failure")
    func responseInterceptorThrowIsNotATransportFailure() async throws {
        InterceptorStubProtocol.configure(body: Data(#"{"a":1}"#.utf8))
        let observer = SpyObserver()
        let client = makeClient(response: [ThrowingResponseInterceptor()], observer: observer)

        await #expect {
            _ = try await client.send(ProbeRequest(sessionToken: nil))
        } throws: { error in
            guard case OryClientError.unexpectedResponse = error else { return false }
            return true
        }

        // The response arrived, so the observer saw it; the interceptor failure is not a
        // transport failure, so the observer is not told the request failed.
        #expect(observer.didReceiveCount == 1)
        #expect(observer.didFailCount == 0)
    }
}

/// Counts observer callbacks for asserting which fired.
final class SpyObserver: OryNetworkObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var receives = 0
    private var failures = 0
    var didReceiveCount: Int { lock.withLock { receives } }
    var didFailCount: Int { lock.withLock { failures } }

    func clientDidReceive(_ response: OryNetworkResponse) {
        lock.withLock { receives += 1 }
    }

    func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable) {
        lock.withLock { failures += 1 }
    }
}

/// Answers every request with a configurable body and status, and captures the request it
/// was handed so tests can assert the headers the client actually sent. Its own protocol,
/// so its process-wide state never races with `StubURLProtocol`.
final class InterceptorStubProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private nonisolated(unsafe) static var body = Data()
    private nonisolated(unsafe) static var statusCode = 200
    private nonisolated(unsafe) static var captured: URLRequest?

    static func configure(body: Data, statusCode: Int = 200) {
        lock.withLock {
            Self.body = body
            Self.statusCode = statusCode
            Self.captured = nil
        }
    }

    static var lastRequest: URLRequest? { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (body, statusCode) = Self.lock.withLock { () -> (Data, Int) in
            Self.captured = request
            return (Self.body, Self.statusCode)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
