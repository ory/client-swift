import Foundation

/// HTTP methods used by the client.
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

/// Header field names, defined once instead of as scattered string literals.
enum HTTPHeader {
    static let accept = "Accept"
    static let contentType = "Content-Type"

    /// The Ory session-token header sent on authenticated requests.
    static let sessionToken = "X-Session-Token"

    /// Names the client package, its version, and the OS, with the value from ``ClientIdentification``.
    static let oryClient = "Ory-Client"
}

/// Media types used by the client.
enum MediaType {
    static let json = "application/json"
}
