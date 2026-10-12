import Foundation
@testable import OryClient

/// Returns a canned response and captures the last resolved request. Used to test
/// ``LiveFrontendRepository`` decoding and status handling without the network.
actor MockHTTPClient: HTTPClient {

    private let status: Int
    private let data: Data
    private let baseURL: URL
    private(set) var lastRequest: ResolvedHTTPRequest?

    init(baseURL: URL = URL(string: "https://example.com")!, data: Data, statusCode: Int) {
        self.baseURL = baseURL
        self.data = data
        self.status = statusCode
    }

    func send<R: FrontendRequest>(_ request: R) async throws -> HTTPResponse<R.Response> {
        lastRequest = try FrontendRequestResolver.resolve(request, baseURL: baseURL)
        return HTTPResponse(status: status, data: data)
    }
}
