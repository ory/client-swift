import Foundation
import Testing
@testable import OryClient

@Suite("HTTPResponse")
struct HTTPResponseTests {

    private struct Probe: Decodable, Sendable, Equatable {
        let a: Int
    }

    @Test("success decodes the declared response body")
    func decodesSuccess() throws {
        let response = HTTPResponse<Probe>(status: 200, data: Data(#"{"a":1}"#.utf8))
        #expect(try response.success() == Probe(a: 1))
    }

    @Test("decode reads an arbitrary DTO from the body")
    func decodesArbitrary() throws {
        let response = HTTPResponse<OryEmptyResponse>(status: 400, data: Data(#"{"a":7}"#.utf8))
        #expect(try response.decode(Probe.self) == Probe(a: 7))
    }

    @Test("an empty body decodes as OryEmptyResponse")
    func emptyBodyIsEmptyResponse() throws {
        let response = HTTPResponse<OryEmptyResponse>(status: 200, data: Data())
        _ = try response.success()
    }

    @Test("a malformed body surfaces as unexpectedResponse")
    func malformedWrapsError() throws {
        let response = HTTPResponse<Probe>(status: 200, data: Data("not json".utf8))
        do {
            _ = try response.success()
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected unexpectedResponse, got \(error)")
                return
            }
        }
    }

    @Test("a non-null body is rejected as an empty response")
    func nonNullIsNotEmpty() throws {
        let response = HTTPResponse<OryEmptyResponse>(status: 200, data: Data(#"{"x":1}"#.utf8))
        do {
            _ = try response.success()
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            guard case .unexpectedResponse = error else {
                Issue.record("expected unexpectedResponse, got \(error)")
                return
            }
        }
    }
}
