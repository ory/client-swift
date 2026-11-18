import Testing
import Ory

@Suite("OryPINPolicy")
struct OryPINPolicyTests {

    @Test("The default policy accepts a PIN of 4 to 32 characters", arguments: [
        "2580", "1357", "0112", "7531", "135791", "1235", "a1b2", String(repeating: "12", count: 16),
    ])
    func defaultAcceptsValidPIN(pin: String) {
        #expect(OryPINPolicy.default.violation(for: pin) == nil)
    }

    @Test("The default policy rejects a PIN shorter than 4 characters", arguments: ["", "1", "258"])
    func defaultRejectsShortPIN(pin: String) {
        #expect(OryPINPolicy.default.violation(for: pin) == .tooShort(minimumLength: 4))
    }

    @Test("The default policy rejects a PIN longer than 32 characters")
    func defaultRejectsLongPIN() {
        let pin = String(repeating: "12", count: 16) + "3"

        #expect(OryPINPolicy.default.violation(for: pin) == .tooLong(maximumLength: 32))
    }

    @Test("The default policy rejects a PIN that repeats one character", arguments: ["0000", "1111", "9999", "777777", "aaaa"])
    func defaultRejectsRepeatedCharacter(pin: String) {
        #expect(OryPINPolicy.default.violation(for: pin) == .repeatedCharacter)
    }

    @Test("The default policy rejects a run of consecutive digits", arguments: ["1234", "0123", "4321", "6789", "9876", "123456", "543210"])
    func defaultRejectsSequentialDigits(pin: String) {
        #expect(OryPINPolicy.default.violation(for: pin) == .sequentialDigits)
    }

    @Test("A custom policy replaces the default rules")
    func customPolicyReplacesDefault() {
        // Given
        let digitsOnly = OryPINPolicy { pin in
            pin.allSatisfy(\.isNumber) ? nil : .custom(message: "Use digits only.")
        }

        // Then
        #expect(digitsOnly.violation(for: "1111") == nil)
        #expect(digitsOnly.violation(for: "abcd") == .custom(message: "Use digits only."))
    }
}
