import Foundation

/// The `URLSession` delegate of the client's session. It follows redirects, but a
/// redirected request that leaves the project origin goes without the session token.
final class SessionTokenRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {

    private let projectURL: URL

    init(projectURL: URL) {
        self.projectURL = projectURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, !url.isSameOrigin(as: projectURL) else {
            completionHandler(request)
            return
        }
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: HTTPHeader.sessionToken)
        completionHandler(redirected)
    }
}

extension URL {

    /// Whether both URLs share scheme, host, and port (RFC 6454 origin), treating an
    /// omitted port as the scheme's default.
    func isSameOrigin(as other: URL) -> Bool {
        guard let scheme = scheme?.lowercased(), scheme == other.scheme?.lowercased(),
              let host = host?.lowercased(), host == other.host?.lowercased()
        else { return false }
        return effectivePort(scheme: scheme) == other.effectivePort(scheme: scheme)
    }

    private func effectivePort(scheme: String) -> Int? {
        if let port { return port }
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
