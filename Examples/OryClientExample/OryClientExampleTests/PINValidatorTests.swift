import Testing
@testable import OryClientExample

@Suite("PIN validator")
@MainActor
struct PINValidatorTests {

    @Test("accepts a 4-to-8 character PIN that isn't all the same digit", arguments: ["1234", "12345", "12345678", "1223", "1122"])
    func acceptsValidPINs(pin: String) {
        #expect(PINValidator(pin: pin).execute().isValid)
    }

    @Test("rejects a PIN shorter than 4", arguments: ["", "1", "12", "123"])
    func rejectsTooShort(pin: String) {
        #expect(firstError(pin) == .invalidLength)
    }

    @Test("rejects a PIN longer than 8")
    func rejectsTooLong() {
        #expect(firstError("123456789") == .invalidLength)
    }

    @Test("rejects a PIN of all the same character", arguments: ["0000", "1111", "111111", "88888888"])
    func rejectsAllSame(pin: String) {
        #expect(firstError(pin) == .allSameCharacters)
    }

    /// The first ``PINValidationError`` the validator reports, or `nil` when the PIN is valid.
    private func firstError(_ pin: String) -> PINValidationError? {
        guard case let .invalid(errors) = PINValidator(pin: pin).execute() else { return nil }
        return errors.compactMap { $0 as? PINValidationError }.first
    }
}
