import Foundation
import Security

/// Derives the Keychain service the default storage uses for a project, so clients configured
/// for different projects in one app never read or overwrite each other's items.
///
/// The path is part of the scope because self-hosted deployments can serve several projects
/// from one host under different paths.
enum KeychainProjectScope {

    /// The service every client shared before items were scoped by project.
    static let unscopedService = "com.ory.client"

    static func service(for projectURL: URL) -> String {
        "\(unscopedService):" + normalized(projectURL)
    }

    /// Deletes the session token and device key earlier versions kept under ``unscopedService``.
    ///
    /// Nothing reads them any more, so left in place they would keep a live token in the
    /// Keychain for good. The query has no access group, so it also matches items an earlier
    /// version stored in a shared one.
    static func removeUnscopedItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unscopedService,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func normalized(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        // The encoded path, because the decoded one turns `%2F` into a separator and would merge
        // `/tenant%2Fa` with `/tenant/a`.
        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        return components.string ?? url.absoluteString
    }
}
