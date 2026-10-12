import Testing
import OryClient

@Suite("OryAuthenticatorAssuranceLevel")
struct AuthenticatorAssuranceLevelTests {

    @Test("orders unknown lowest, then aal0 through aal3")
    func ordering() {
        #expect(OryAuthenticatorAssuranceLevel.unknown < .aal0)
        #expect(OryAuthenticatorAssuranceLevel.aal0 < .aal1)
        #expect(OryAuthenticatorAssuranceLevel.aal1 < .aal2)
        #expect(OryAuthenticatorAssuranceLevel.aal2 < .aal3)
    }
}
