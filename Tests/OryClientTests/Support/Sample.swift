import Foundation
import OryClient

enum Sample {

    static func session(
        id: String = "session-1",
        assuranceLevel: OryAuthenticatorAssuranceLevel = .aal1,
        identity: OryIdentity? = nil
    ) -> OrySession {
        OrySession(
            id: id,
            isActive: true,
            expiresAt: nil,
            authenticatedAt: nil,
            authenticatorAssuranceLevel: assuranceLevel,
            identity: identity
        )
    }

    static func identity(id: String = "identity-1") -> OryIdentity {
        OryIdentity(id: id, schemaID: "default")
    }

    static func flow(id: String = "flow-1", kind: OryFlowKind = .login) -> OryFlow {
        OryFlow(id: id, kind: kind, expiresAt: .distantFuture)
    }

    static func loginFlow(id: String = "flow-1") -> OryFlow {
        flow(id: id, kind: .login)
    }

    /// A submit button that selects a method (defaults to the password strategy).
    static func submitAction(value: String = "password") -> OryInputField {
        OryInputField(name: .method, kind: .submit, value: value)
    }
}
