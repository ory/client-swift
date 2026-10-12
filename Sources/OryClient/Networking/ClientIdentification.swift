import Foundation

/// Identifies this package to the Ory backend through the ``HTTPHeader/oryClient`` header,
/// so Ory can see which client versions still call the API.
enum ClientIdentification {

    /// The package version. Must equal the release tag of the version being published.
    static let version = "0.1.0"

    /// For example `ory-client-swift/0.1.0 (iOS 18.2.0)`.
    static let headerValue = "ory-client-swift/\(version) (\(operatingSystem))"

    private static var operatingSystem: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let name = "iOS"
        #else
        let name = "macOS"
        #endif
        return "\(name) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}
