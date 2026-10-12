import Foundation

/// The result of a completed verification.
///
/// Verification confirms an address (email or phone); it returns no session or
/// identity, so this is a marker that the flow reached its verified state.
public struct OryVerificationResult: Sendable {
    public init() {}
}

/// A pending verification surfaced by registration before sign-in, or by settings
/// when the project requires confirmation of a new address before applying a change.
///
/// Render it by fetching the flow with ``OryClientProtocol/getVerificationFlow(id:)``,
/// then submit as usual.
public struct OryVerificationHandle: Sendable, Hashable {

    /// The id of the verification flow already created for the identity.
    public let flowID: String

    /// The address (email or phone) being verified.
    public let address: String

    public init(flowID: String, address: String) {
        self.flowID = flowID
        self.address = address
    }
}
