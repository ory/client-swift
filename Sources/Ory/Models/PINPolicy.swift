/// The rule a PIN must follow before `OryClient` enrolls a device with it or sets it as the new
/// PIN.
///
/// The PIN never leaves the device, so the Ory server cannot check it. `OryClient` checks it
/// instead: ``OryDeviceEnrollment/enrollDevice(name:protection:)`` with
/// ``OryDeviceProtection/pin(_:)`` and ``OryDeviceManagement/resetDevicePIN(newPin:)`` throw
/// ``OryClientError/pinPolicyViolation(_:)`` for a PIN that breaks the policy, before any
/// request is sent. Signing in and stepping up with an existing PIN are not checked.
///
/// The ``default`` policy rejects a PIN that:
/// - has fewer than ``defaultMinimumLength`` (4) characters,
/// - has more than ``defaultMaximumLength`` (32) characters,
/// - repeats one character, such as `0000` or `aaaa`,
/// - is a run of consecutive digits, such as `1234` or `9876`.
///
/// Set your own policy in ``OryClientConfiguration/pinPolicy``.
/// It replaces the default entirely, so check ``default`` inside it to keep the default rules:
///
/// ```swift
/// let sixDigits = OryPINPolicy { pin in
///     if let violation = OryPINPolicy.default.violation(for: pin) { return violation }
///     guard pin.count >= 6 else { return .tooShort(minimumLength: 6) }
///     return pin.allSatisfy(\.isNumber) ? nil : .custom(message: String(localized: "Use digits only."))
/// }
/// let configuration = OryClientConfiguration(projectURL: projectURL, pinPolicy: sixDigits)
/// ```
///
/// Check the PIN with ``violation(for:)`` while the user types, to show the problem before
/// calling `OryClient`.
public struct OryPINPolicy: Sendable {

    /// Why a PIN does not follow the policy.
    public enum Violation: Sendable, Hashable {

        /// The PIN has fewer characters than `minimumLength`. An empty PIN is too short.
        case tooShort(minimumLength: Int)

        /// The PIN has more characters than `maximumLength`.
        case tooLong(maximumLength: Int)

        /// Every character of the PIN is the same, such as `1111`.
        case repeatedCharacter

        /// The PIN is a run of consecutive digits, ascending or descending, such as `1234` or
        /// `9876`.
        case sequentialDigits

        /// A rule of your own policy. Pass text that is already localized, so you can show
        /// `message` as given.
        case custom(message: String)
    }

    private let check: @Sendable (String) -> Violation?

    /// Creates a policy from your own rule.
    ///
    /// The rule replaces the ``default`` policy. Call `OryPINPolicy.default.violation(for:)`
    /// inside it to keep the default rules and add your own.
    ///
    /// - Parameter check: Returns the violation for a PIN that breaks the rule, or `nil` for a
    ///   valid PIN. Keep it fast: it can run on every change of a PIN field.
    public init(_ check: @escaping @Sendable (_ pin: String) -> Violation?) {
        self.check = check
    }

    /// Checks a PIN against the policy.
    ///
    /// - Parameter pin: The PIN the user entered.
    /// - Returns: The violation, or `nil` when the PIN follows the policy.
    public func violation(for pin: String) -> Violation? {
        check(pin)
    }

    /// The fewest characters the ``default`` policy accepts.
    public static let defaultMinimumLength = 4

    /// The most characters the ``default`` policy accepts.
    public static let defaultMaximumLength = 32

    /// The default policy: 4 to 32 characters, not all the same character, and not a run of
    /// consecutive digits.
    ///
    /// Characters, not digits: letters and symbols count too, so a passcode typed on the full
    /// keyboard works as well as a numeric PIN.
    public static let `default` = OryPINPolicy { pin in
        let characters = Array(pin)
        if characters.count < defaultMinimumLength {
            return .tooShort(minimumLength: defaultMinimumLength)
        }
        if characters.count > defaultMaximumLength {
            return .tooLong(maximumLength: defaultMaximumLength)
        }
        if Set(characters).count == 1 {
            return .repeatedCharacter
        }
        if isSequentialDigits(characters) {
            return .sequentialDigits
        }
        return nil
    }

    private static func isSequentialDigits(_ characters: [Character]) -> Bool {
        let digits = characters.compactMap { $0.isASCII ? $0.wholeNumberValue : nil }
        guard digits.count == characters.count, let first = digits.first, let second = digits.dropFirst().first else {
            return false
        }
        let step = second - first
        guard abs(step) == 1 else { return false }
        return zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == step }
    }
}
