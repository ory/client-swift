import Foundation

/// How strongly a session is authenticated.
///
/// A higher level means more authentication factors were used, making the account
/// harder to compromise:
///
/// - ``aal1``: a single factor, such as a password or social sign-in.
/// - ``aal2``: two factors, such as a password plus a one-time code or a bound device.
/// - ``aal3``: a hardware-bound factor.
///
/// Use this to decide whether to prompt the user for a step-up, for example before
/// showing sensitive settings:
///
/// ```swift
/// let session = try await client.currentSession()
/// if session.authenticatorAssuranceLevel < .aal2 {
///     // Prompt the user to complete a second factor.
/// }
/// ```
///
/// - Important: New cases are added in minor releases. End a `switch` that lists every case
///   with `@unknown default:`, so a new case raises a warning instead of a build error, or use
///   `default:` when you handle only some cases.
public enum OryAuthenticatorAssuranceLevel: String, Sendable, Hashable, Comparable {

    /// No authentication has taken place.
    case aal0

    /// One authentication factor was used.
    case aal1

    /// Two authentication factors were used.
    case aal2

    /// A hardware-bound authentication factor was used.
    case aal3

    /// A level this version of the client does not recognize, sent by a newer backend.
    case unknown

    public static func < (lhs: OryAuthenticatorAssuranceLevel, rhs: OryAuthenticatorAssuranceLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .unknown: return -1
        case .aal0: return 0
        case .aal1: return 1
        case .aal2: return 2
        case .aal3: return 3
        }
    }
}
