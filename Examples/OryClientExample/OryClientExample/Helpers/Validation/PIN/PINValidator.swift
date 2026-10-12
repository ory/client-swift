/// Validates a user-chosen PIN against this app's policy: between ``minLength`` and
/// ``maxLength`` characters, and not all the same character (e.g. `0000`, `111111`).
///
/// `OryClient` does **not** validate PINs — the server never sees the PIN, so policy
/// enforcement is the integrating app's responsibility. This validator shows one way to do it,
/// reusing the small declarative validation engine in the `Validation` folder. Run it before
/// calling `enrollDevice(name:protection: .pin(_:))` or `resetDevicePIN` and block the call
/// when it fails.
///
/// ```swift
/// switch PINValidator(pin: entered).execute() {
/// case .valid:
///     try await client.enrollDevice(name: deviceName, protection: .pin(entered))
/// case let .invalid(errors):
///     show(errors.first?.localizedDescription)
/// }
/// ```
struct PINValidator: ValidationExecutor {

    /// The shortest allowed PIN.
    nonisolated static let minLength: UInt = 4
    /// The longest allowed PIN.
    nonisolated static let maxLength: UInt = 8

    let pin: String

    init(pin: String) {
        self.pin = pin
    }

    func execute() -> ValidationResult {
        Validation(input: pin)
            .match(rule: .hasNumberOfElements(in: Self.minLength...Self.maxLength, error: PINValidationError.invalidLength))
            // With no `minFailingLength`, this rejects a PIN only when *every* character is the
            // same (0000, 111111) — the whole string is one consecutive run.
            .match(rule: .hasNotConsecutiveCharacters(error: PINValidationError.allSameCharacters))
            .accumulatedResult
    }
}
