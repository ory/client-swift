import Testing
import OryClient

@Suite("OryFormValues")
struct OryFormValuesTests {

    @Test("prefills from a flow and reads by field and by typed name")
    func prefill() {
        // Given a flow with one prefilled input
        let field = OryInputField(name: .identifier, kind: .text, value: "seed@x.com")
        let node = OryNode(id: "identifier", group: .password, content: .input(field))
        let flow = OryFlow(id: "f", kind: .login, expiresAt: .distantFuture, nodes: [node])

        // When
        var values = flow.makeValues()

        // Then it is prefilled with the server default, reachable by field or by name —
        // note: no `?? ""` needed, the subscript always returns a value
        #expect(values[field] == "seed@x.com")
        #expect(values[.identifier] == "seed@x.com")

        // And writing by name is visible when reading by field
        values[.identifier] = "new@x.com"
        #expect(values[field] == "new@x.com")
    }

    @Test("returns an empty string for fields it has no value for")
    func emptyDefault() {
        let values = OryFormValues()
        let field = OryInputField(name: .password, kind: .password)
        #expect(values[field] == "")
        #expect(values[.password] == "")
    }
}
