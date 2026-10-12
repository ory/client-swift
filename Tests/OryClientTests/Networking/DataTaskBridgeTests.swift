import Foundation
import Testing
@testable import OryClient

/// Covers the transport used below iOS 15, which no test destination runs, by calling it
/// directly. Serialized because the stub's response is process-wide state. The stub's
/// bounded `waitUntil` loops and task cancellation guarantee each test finishes rather than
/// hanging. (No `.timeLimit` trait: it is `Duration`-based and unavailable at the package's
/// iOS 14 deployment target.)
@Suite("URLSessionHTTPClient dataTask bridge", .serialized)
struct DataTaskBridgeTests {

    private let url = URL(string: "https://example.ory/flows")!

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("Returns the body and the HTTP response")
    func returnsResponse() async throws {
        // Given
        StubURLProtocol.stub = .responding(statusCode: 201, body: Data("created".utf8))

        // When
        let (data, response) = try await URLSessionHTTPClient.dataTaskBridge(
            for: URLRequest(url: url),
            session: makeSession()
        )

        // Then
        #expect(data == Data("created".utf8))
        #expect((response as? HTTPURLResponse)?.statusCode == 201)
    }

    @Test("Surfaces a transport failure as its URLError")
    func surfacesTransportError() async throws {
        // Given
        StubURLProtocol.stub = .failing(URLError(.notConnectedToInternet))

        // When / Then
        await #expect {
            _ = try await URLSessionHTTPClient.dataTaskBridge(for: URLRequest(url: url), session: makeSession())
        } throws: { error in
            (error as? URLError)?.code == .notConnectedToInternet
        }
    }

    // Cancellation has two paths: before and after the URLSession task exists. Both must
    // end as `URLError.cancelled`; cancelling immediately exercises the second. The stub
    // never answers, so cancellation is the only way these can finish.

    @Test("Cancelling in flight throws URLError.cancelled")
    func cancellingInFlight() async throws {
        // Given
        StubURLProtocol.stub = .hanging
        let session = makeSession()
        let request = URLRequest(url: url)

        // When
        let inFlight = Task { try await URLSessionHTTPClient.dataTaskBridge(for: request, session: session) }
        try await StubURLProtocol.waitUntilLoading()
        inFlight.cancel()

        // Then
        await #expect { _ = try await inFlight.value } throws: { isCancelled($0) }
        #expect(await StubURLProtocol.waitUntilStopped(), "URLSession must have cancelled the underlying load")
    }

    @Test("Cancelling before the task starts throws URLError.cancelled")
    func cancellingImmediately() async throws {
        // Given
        StubURLProtocol.stub = .hanging
        let session = makeSession()
        let request = URLRequest(url: url)

        // When
        let inFlight = Task { try await URLSessionHTTPClient.dataTaskBridge(for: request, session: session) }
        inFlight.cancel()

        // Then
        await #expect { _ = try await inFlight.value } throws: { isCancelled($0) }
    }

    private func isCancelled(_ error: any Error) -> Bool {
        (error as? URLError)?.code == .cancelled
    }
}

/// Answers requests from a process-wide stub. Responses are delivered synchronously from
/// `startLoading()`, so no test depends on a timer firing; `hanging` never answers at all,
/// which is what the cancellation tests need.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Stub: Sendable {
        var statusCode = 200
        var body = Data()
        var error: URLError?
        /// When false the request is left pending until `stopLoading()`.
        var answers = true

        static func responding(statusCode: Int, body: Data) -> Stub {
            Stub(statusCode: statusCode, body: body)
        }

        static func failing(_ error: URLError) -> Stub {
            Stub(error: error)
        }

        static let hanging = Stub(answers: false)
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var currentStub = Stub()
    private nonisolated(unsafe) static var loading = false
    private nonisolated(unsafe) static var stopped = false

    static var stub: Stub {
        get { lock.withLock { currentStub } }
        set {
            lock.withLock {
                currentStub = newValue
                loading = false
                stopped = false
            }
        }
    }

    /// Resolves once URLSession has handed the request to the protocol, so a test can
    /// cancel a load that has demonstrably started rather than guessing with a sleep.
    static func waitUntilLoading() async throws {
        try await waitUntil { lock.withLock { loading } }
    }

    /// URLSession calls `stopLoading()` on cancellation, but not necessarily before the
    /// task's completion handler runs — hence the wait rather than a bare read.
    static func waitUntilStopped() async -> Bool {
        (try? await waitUntil { lock.withLock { stopped } }) != nil
    }

    private static func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw StubTimeout()
    }

    struct StubTimeout: Error {}

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.lock.withLock {
            Self.loading = true
            return Self.currentStub
        }
        guard stub.answers else { return }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.lock.withLock { Self.stopped = true }
    }
}
