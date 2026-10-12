import Testing
import OryClient

@Suite("OryFieldName")
struct OryFieldNameTests {

    @Test("constants carry the names Ory sends")
    func wireNames() {
        #expect(OryFieldName.password.rawValue == "password")
        #expect(OryFieldName.totpCode.rawValue == "totp_code")
        #expect(OryFieldName.lookupSecret.rawValue == "lookup_secret")
        #expect(OryFieldName.csrfToken.rawValue == "csrf_token")
    }

    @Test("a name built from a string equals the constant for the same name")
    func comparesByRawValue() {
        // Given names an app builds itself, as it must for fields this build has no constant for
        let password = OryFieldName(rawValue: "password")
        let trait = OryFieldName(rawValue: "traits.email")

        // Then they match the constants and each other by name alone
        #expect(password == .password)
        #expect(trait == OryFieldName(rawValue: "traits.email"))
        #expect(trait != .identifier)
    }
}
