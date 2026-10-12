#if DEBUG
import Foundation
import OryClient

nonisolated enum DebugHeader {
    static let correlationID = "X-Ory-Debug-Id"
}

/// Records every outgoing request into the ``NetworkHistoryStore`` and stamps it with a
/// correlation id, so the response and failure can be matched back to it.
///
/// This is the request half of the in-app network logger — it shows integrators that
/// ``OryRequestInterceptor`` is enough to observe (and here, tag) every request. It runs
/// before the client applies the session token, so the token never enters the log.
struct LoggingRequestInterceptor: OryRequestInterceptor {

    let store: NetworkHistoryStore

    func intercept(_ request: OryOutgoingRequest) async throws -> OryOutgoingRequest {
        var request = request
        let id = UUID()
        request.headers[DebugHeader.correlationID] = id.uuidString
        await store.recordRequest(
            id: id,
            method: request.method,
            url: request.url,
            headers: request.headers,
            body: request.body
        )
        return request
    }
}

/// Attaches every response to its request in the ``NetworkHistoryStore``, matched by the
/// correlation id the request interceptor stamped.
struct LoggingResponseInterceptor: OryResponseInterceptor {

    let store: NetworkHistoryStore

    func intercept(_ response: OryReceivedResponse) async throws -> OryReceivedResponse {
        if let id = response.request.headers[DebugHeader.correlationID].flatMap(UUID.init(uuidString:)) {
            await store.recordResponse(
                id: id,
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body
            )
        }
        return response
    }
}

/// Prints every request/response to the console (like ``OryConsoleNetworkObserver``) and,
/// additionally, records transport failures into the ``NetworkHistoryStore``.
///
/// Failures do not flow through the response interceptor — a request that never gets a
/// response throws instead — so the observer is where the in-app log learns about them.
struct DebugNetworkObserver: OryNetworkObserver {

    let store: NetworkHistoryStore
    private let console = OryConsoleNetworkObserver()

    func clientWillSend(_ request: OryNetworkRequest) {
        console.clientWillSend(request)
    }

    func clientDidReceive(_ response: OryNetworkResponse) {
        console.clientDidReceive(response)
    }

    func clientDidFail(_ request: OryNetworkRequest, error: any Error & Sendable) {
        console.clientDidFail(request, error: error)
        guard let id = request.headers[DebugHeader.correlationID].flatMap(UUID.init(uuidString:)) else { return }
        let message = String(describing: error)
        Task { await store.recordFailure(id: id, message: message) }
    }
}
#endif
