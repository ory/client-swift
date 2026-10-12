import Foundation

/// The registration flow's data operations.
protocol RegistrationRepository: Sendable {

    /// Creates a native registration flow and maps it to a renderable ``OryFlow``.
    func createRegistrationFlow() async throws -> OryFlow

    /// Submits the merged form to a registration flow's action URL.
    func submitRegistration(url: URL, fields: [String: String], sessionToken: String?) async throws -> RegistrationOutcome
}

/// The internal outcome of submitting a registration flow.
enum RegistrationOutcome: Sendable {

    /// The identity was created. `session`/`token` are present only when the project
    /// signs the user in after registration (the client stores the token when so);
    /// `verification` is present when the project requires verification instead.
    case success(identity: OryIdentity, session: OrySession?, token: String?, verification: OryVerificationHandle?)

    /// Validation failed or another step is required; re-render the flow.
    case pending(OryFlow)
}
