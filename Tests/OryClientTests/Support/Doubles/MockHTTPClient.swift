import Foundation
@testable import Ory

/// Returns canned responses in order, repeating the last one, and captures the resolved
/// requests. Used to test ``LiveFrontendRepository`` decoding and status handling without the
/// network.
actor MockHTTPClient: HTTPClient {

    private let responses: [(status: Int, data: Data)]
    private let baseURL: URL
    private(set) var requests: [ResolvedHTTPRequest] = []

    var lastRequest: ResolvedHTTPRequest? { requests.last }

    init(baseURL: URL = URL(string: "https://example.com")!, data: Data, statusCode: Int) {
        self.init(baseURL: baseURL, responses: [(statusCode, data)])
    }

    init(baseURL: URL = URL(string: "https://example.com")!, responses: [(status: Int, data: Data)]) {
        precondition(!responses.isEmpty, "MockHTTPClient needs at least one response")
        self.baseURL = baseURL
        self.responses = responses
    }

    func send<R: FrontendRequest>(_ request: R) async throws -> HTTPResponse<R.Response> {
        requests.append(try FrontendRequestResolver.resolve(request, baseURL: baseURL))
        let response = responses[min(requests.count, responses.count) - 1]
        return HTTPResponse(status: response.status, data: response.data)
    }
}
