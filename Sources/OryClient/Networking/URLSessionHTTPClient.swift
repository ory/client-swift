import Foundation

/// The production ``HTTPClient``.
///
/// Resolves a typed ``FrontendRequest`` against the project base URL, runs the request
/// through the interceptor chain, sends it with modern async `URLSession`, runs the
/// response through its interceptor chain, and reports activity to an ``OryNetworkObserver``.
///
/// Implemented as an `actor`. There is no mutable state to protect, but it keeps all
/// networking in one isolation domain; because actors are reentrant across `await`,
/// in-flight requests still run concurrently — only the brief request-building is
/// serialized.
actor URLSessionHTTPClient: HTTPClient {

    private let baseURL: URL
    private let urlSession: URLSession
    private let transport: HTTPTransport
    private let requestInterceptors: [any OryRequestInterceptor]
    private let responseInterceptors: [any OryResponseInterceptor]
    private let observer: (any OryNetworkObserver)?

    init(
        baseURL: URL,
        urlSession: URLSession? = nil,
        transport: HTTPTransport = .automatic,
        requestInterceptors: [any OryRequestInterceptor] = [],
        responseInterceptors: [any OryResponseInterceptor] = [],
        observer: (any OryNetworkObserver)? = nil
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession ?? Self.makeSession(projectURL: baseURL)
        self.transport = transport
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.observer = observer
    }

    /// Builds the transport session for Ory's native (API-type) flows.
    ///
    /// API flows authenticate with the `X-Session-Token` header and reject any request
    /// that carries a `Cookie` header: a cookie signals a browser and a possible CSRF
    /// vector (Ory error 4000001). `URLSession.shared` stores and replays cookies — for
    /// example Cloudflare's `__cf_bm` / `__cflb`, set while creating a flow — which would
    /// trip that check on the flow's next request. This session never stores or sends
    /// cookies, and its ``SessionTokenRedirectGuard`` keeps the session token from following
    /// a redirect out of the project origin.
    static func makeSession(
        projectURL: URL,
        configuration: URLSessionConfiguration = .default
    ) -> URLSession {
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        return URLSession(
            configuration: configuration,
            delegate: SessionTokenRedirectGuard(projectURL: projectURL),
            delegateQueue: nil
        )
    }

    func send<R: FrontendRequest>(_ request: R) async throws -> HTTPResponse<R.Response> {
        let resolved = try FrontendRequestResolver.resolve(request, baseURL: baseURL)

        let urlRequest: URLRequest
        let outgoing: OryOutgoingRequest
        let event: OryNetworkRequest
        do {
            (urlRequest, outgoing, event) = try await makeURLRequest(resolved)
        } catch let error as OryClientError {
            throw error
        } catch {
            // A request interceptor threw before anything was sent — a client-side request
            // failure, not a transport failure, so it is not reported to the observer.
            throw OryClientError.unexpectedResponse(underlying: UnderlyingError(error))
        }

        observer?.clientWillSend(event)
        let start = Date()

        // The transport. A failure here means no response arrived, so the observer is told.
        let responseData: Data
        let httpResponse: HTTPURLResponse
        do {
            let (bytes, response) = try await self.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                let error = URLError(.badServerResponse)
                observer?.clientDidFail(event, error: error)
                throw OryClientError.network(underlying: error)
            }
            responseData = bytes
            httpResponse = http
        } catch let error as OryClientError {
            throw error
        } catch let error as URLError {
            observer?.clientDidFail(event, error: error)
            throw OryClientError.network(underlying: error)
        } catch {
            let wrapped = UnderlyingError(error)
            observer?.clientDidFail(event, error: wrapped)
            throw OryClientError.network(underlying: wrapped)
        }

        observer?.clientDidReceive(
            OryNetworkResponse(request: event, statusCode: httpResponse.statusCode, duration: Date().timeIntervalSince(start))
        )

        // Applying the response interceptors is a post-response processing step, not a
        // transport event: a throw here is surfaced to the caller as `unexpectedResponse`,
        // but the observer — which already saw the response — is not told the request failed.
        let headers = Self.headerFields(httpResponse)
        let received = OryReceivedResponse(
            request: outgoing,
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: CredentialRedaction.redact(responseData) ?? Data()
        )
        do {
            for interceptor in responseInterceptors {
                try await interceptor.intercept(received)
            }
            return HTTPResponse(status: httpResponse.statusCode, data: responseData, headers: headers)
        } catch let error as OryClientError {
            throw error
        } catch {
            throw OryClientError.unexpectedResponse(underlying: UnderlyingError(error))
        }
    }

    private func data(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        if transport == .automatic, #available(iOS 15.0, macOS 12.0, *) {
            return try await urlSession.data(for: urlRequest)
        }
        return try await Self.dataTaskBridge(for: urlRequest, session: urlSession)
    }

    /// Applies the request interceptor chain, builds the `URLRequest`, then applies the session
    /// token directly on it (kept out of the returned `OryOutgoingRequest`). Returns that
    /// outgoing request (token-free, for the response interceptors) and a redacted event (for
    /// the observer). Made `internal` so tests can assert header handling without the network.
    func makeURLRequest(_ resolved: ResolvedHTTPRequest) async throws -> (URLRequest, OryOutgoingRequest, OryNetworkRequest) {
        var headers: [String: String] = [
            HTTPHeader.accept: MediaType.json,
            HTTPHeader.oryClient: ClientIdentification.headerValue,
        ]
        if resolved.body != nil {
            headers[HTTPHeader.contentType] = MediaType.json
        }

        var outgoing = OryOutgoingRequest(
            method: resolved.method.rawValue,
            url: resolved.url,
            headers: headers,
            body: CredentialRedaction.redact(resolved.body)
        )
        for interceptor in requestInterceptors {
            outgoing.headers = try await interceptor.intercept(outgoing).headers
        }
        var urlRequest = URLRequest(url: resolved.url)
        urlRequest.httpMethod = resolved.method.rawValue
        urlRequest.httpBody = resolved.body
        for (name, value) in outgoing.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        // The session token is applied last and directly on the `URLRequest` — after the
        // interceptor chain and the header projection. It never enters `outgoing` (which is
        // also handed to the response interceptors), so an interceptor can neither read it nor
        // overwrite it: `setValue(_:forHTTPHeaderField:)` is case-insensitive, so it wins over
        // any header an interceptor set under a differently-cased name.
        if let sessionToken = resolved.sessionToken {
            guard resolved.url.isSameOrigin(as: baseURL) else {
                throw OryClientError.unexpectedResponse(
                    underlying: UnderlyingError(URLError(.badURL, userInfo: [
                        NSLocalizedDescriptionKey: "Refusing to send the session token outside the project origin.",
                    ]))
                )
            }
            urlRequest.setValue(sessionToken, forHTTPHeaderField: HTTPHeader.sessionToken)
        }

        // The observer sees the interceptor-visible headers plus a redacted marker when a token
        // was applied — never the token itself.
        var safeHeaders = outgoing.headers
        if resolved.sessionToken != nil {
            safeHeaders[HTTPHeader.sessionToken] = "***"
        }
        let event = OryNetworkRequest(method: outgoing.method, url: outgoing.url, headers: safeHeaders)

        return (urlRequest, outgoing, event)
    }

    private static func headerFields(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let name = pair.key as? String, let value = pair.value as? String {
                result[name] = value
            }
        }
    }
}

extension URLSessionHTTPClient {

    /// Awaits a completion-handler `dataTask`, the transport below iOS 15, preserving
    /// cancellation. Independent of the availability check so tests can reach it on any
    /// OS version; no CI destination runs iOS 14.
    static func dataTaskBridge(for urlRequest: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        let taskBox = CancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                taskBox.activate(task)
            }
        } onCancel: {
            taskBox.cancel()
        }
    }
}

/// Bridges a `URLSessionTask` into structured cancellation. The cancellation handler can
/// fire before the continuation body finishes creating the task, so `cancel()` before
/// `activate(_:)` marks the box and the task is cancelled the moment it arrives.
private final class CancellableTaskBox: @unchecked Sendable {

    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    /// Adopts the freshly created task: resumes it, or cancels it immediately when the
    /// box was already cancelled. URLSession still calls the completion handler of a
    /// cancelled task (with `URLError.cancelled`), so the continuation always resumes.
    func activate(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            task.cancel()
        }
        task.resume()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
