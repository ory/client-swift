/// The step a flow is at, as Ory reports it — for example ``chooseMethod`` before the user picked
/// a method, or ``sentEmail`` after Ory emailed a one-time code.
///
/// Read it from ``OryFlow/state`` together with ``OryFlow/activeMethod`` to decide which screen
/// to show:
///
/// ```swift
/// switch (flow.activeMethod, flow.state) {
/// case (.code, .sentEmail):
///     // Ask for the code Ory sent.
/// case (.code, .chooseMethod):
///     // Ask for the email address to send a code to.
/// default:
///     // Render the form from flow.nodes.
/// }
/// ```
///
/// Ory marks this field as experimental and may add values. Compare against the constants below
/// and fall back to rendering the form for anything else, including a `nil` state.
public struct OryFlowState: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

    /// The state as Ory sends it, for example `sent_email`.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public extension OryFlowState {
    /// The user has not chosen a method yet, or a code method still needs the address to send to.
    /// The first state of login, registration and verification flows, and of a recovery flow
    /// unless the project lets the user choose a recovery address (then
    /// ``recoveryAwaitingAddress``).
    static let chooseMethod = OryFlowState(rawValue: "choose_method")

    /// Ory sent a one-time code or a link to the user's address. Show the code field.
    static let sentEmail = OryFlowState(rawValue: "sent_email")

    /// The user entered a valid code or opened a valid link. A recovery flow continues with a
    /// settings flow; a verification flow is complete.
    static let passedChallenge = OryFlowState(rawValue: "passed_challenge")

    /// A settings flow that shows its form. The first state of every settings flow.
    static let showForm = OryFlowState(rawValue: "show_form")

    /// A settings flow whose last change was saved.
    static let success = OryFlowState(rawValue: "success")

    /// A recovery flow that waits for the address to recover.
    static let recoveryAwaitingAddress = OryFlowState(rawValue: "recovery_awaiting_address")

    /// A recovery flow that waits for the user to choose one of several recovery addresses.
    static let recoveryAwaitingAddressChoice = OryFlowState(rawValue: "recovery_awaiting_address_choice")

    /// A recovery flow that waits for the user to confirm the masked address to send a code to.
    static let recoveryConfirmingAddress = OryFlowState(rawValue: "recovery_confirming_address")

    /// A recovery flow that sent a code and waits for it.
    static let recoveryAwaitingCode = OryFlowState(rawValue: "recovery_awaiting_code")
}
