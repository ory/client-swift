import Testing
import Ory

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

    @Test("Given the user typed an identifier, when the next flow still asks for it, then makeValues(keeping:) keeps it")
    func keepsTypedValue() {
        // Given
        var typed = OryFormValues()
        typed[.identifier] = "alice@acme.com"
        let next = flow(inputs: [OryInputField(name: .identifier, kind: .text)])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.identifier] == "alice@acme.com")
    }

    @Test("Given the user typed a password, when the next flow still asks for it, then makeValues(keeping:) clears it")
    func dropsPassword() {
        // Given
        var typed = OryFormValues()
        typed[.identifier] = "alice@acme.com"
        typed[.password] = "hunter2"
        let next = flow(inputs: [
            OryInputField(name: .identifier, kind: .text),
            OryInputField(name: .password, kind: .password),
        ])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.password] == "")
        #expect(values[.identifier] == "alice@acme.com")
    }

    @Test("Given the next flow prefills its password, when keeping the typed values, then makeValues(keeping:) still clears it")
    func clearsPrefilledPassword() {
        // Given
        var typed = OryFormValues()
        typed[.password] = "hunter2"
        let next = flow(inputs: [OryInputField(name: .password, kind: .password, value: "seeded")])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.password] == "")
    }

    @Test("Given the user typed one-time codes, when the next flow still asks for them, then makeValues(keeping:) clears them")
    func clearsOneTimeCodes() {
        // Given
        let lookupSecret = OryFieldName(rawValue: "lookup_secret")
        let emailedCode = OryFieldName(rawValue: "verification_code")
        var typed = OryFormValues()
        typed[.identifier] = "alice@acme.com"
        typed[.code] = "123456"
        typed[.totpCode] = "654321"
        typed[lookupSecret] = "a1b2c3d4"
        typed[emailedCode] = "112233"
        let next = flow(inputs: [
            OryInputField(name: .identifier, kind: .text),
            OryInputField(name: .code, kind: .text, value: "999999"),
            OryInputField(name: .totpCode, kind: .text),
            OryInputField(name: lookupSecret, kind: .text),
            OryInputField(name: emailedCode, kind: .text, autocomplete: .oneTimeCode),
        ])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.identifier] == "alice@acme.com")
        #expect(values[.code] == "")
        #expect(values[.totpCode] == "")
        #expect(values[lookupSecret] == "")
        #expect(values[emailedCode] == "")
    }

    @Test("Given the user typed into a field, when the next flow no longer has it, then makeValues(keeping:) drops the value")
    func dropsValueOfGoneField() {
        // Given
        var typed = OryFormValues()
        typed[.identifier] = "alice@acme.com"
        typed[.code] = "123456"
        let next = flow(inputs: [OryInputField(name: .identifier, kind: .text)])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        var expected = next.makeValues()
        expected[.identifier] = "alice@acme.com"
        #expect(values == expected)
    }

    @Test("Given the user left a field empty, when the next flow prefills it, then makeValues(keeping:) keeps the server's value")
    func keepsServerValueOverEmptyEntry() {
        // Given
        var typed = OryFormValues()
        typed[.identifier] = ""
        let next = flow(inputs: [OryInputField(name: .identifier, kind: .text, value: "seed@acme.com")])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.identifier] == "seed@acme.com")
    }

    @Test("Given the user typed over a prefilled field, when the next flow prefills it again, then makeValues(keeping:) keeps the typed value")
    func prefersTypedValueOverServerValue() {
        // Given
        var typed = OryFormValues()
        typed[.identifier] = "alice@acme.com"
        let next = flow(inputs: [OryInputField(name: .identifier, kind: .text, value: "seed@acme.com")])

        // When
        let values = next.makeValues(keeping: typed)

        // Then
        #expect(values[.identifier] == "alice@acme.com")
    }

    private func flow(inputs: [OryInputField]) -> OryFlow {
        OryFlow(
            id: "next",
            kind: .login,
            nodes: inputs.map { OryNode(id: $0.name.rawValue, group: .default, content: .input($0)) }
        )
    }
}
