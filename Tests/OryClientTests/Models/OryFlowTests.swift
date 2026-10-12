import Foundation
import Testing
@testable import OryClient

@Suite("OryFlow.makeBody")
struct OryFlowTests {

    @Test("merges hidden defaults, user values, and the pressed action")
    func merge() {
        // Given a flow carrying a hidden csrf and a default identifier, plus a submit action
        let action = Sample.submitAction()
        let flow = OryFlow(
            id: "f",
            kind: .login,
            expiresAt: .distantFuture,
            messages: [],
            nodes: [],
            actions: [action],
            submission: OrySubmission(
                action: URL(string: "https://example.com/login")!,
                method: "POST",
                values: ["csrf_token": "abc", "identifier": ""]
            )
        )

        var values = OryFormValues()
        values[.identifier] = "user@x.com"

        // When
        let body = flow.makeBody(values: values, pressing: action)

        // Then
        #expect(body.url.absoluteString == "https://example.com/login")
        #expect(body.fields["csrf_token"] == "abc")        // hidden field carried through
        #expect(body.fields["identifier"] == "user@x.com") // user value overrides the default
        #expect(body.fields["method"] == "password")       // pressed action applied last
    }

    @Test("trims whitespace from email and identifier values, leaving other fields intact")
    func trimsEmailLikeFields() {
        // Given a flow with an identifier (plain text), an email trait, and a password field
        let action = Sample.submitAction()
        let flow = OryFlow(
            id: "f",
            kind: .registration,
            expiresAt: .distantFuture,
            messages: [],
            nodes: [
                OryNode(id: "identifier", group: .password, content: .input(OryInputField(name: .identifier, kind: .text))),
                OryNode(id: "traits.email", group: .profile, content: .input(OryInputField(name: OryFieldName(rawValue: "traits.email"), kind: .email))),
                OryNode(id: "password", group: .password, content: .input(OryInputField(name: .password, kind: .password))),
            ],
            actions: [action]
        )

        var values = OryFormValues()
        values[.identifier] = "  user@x.com \n"
        values[OryFieldName(rawValue: "traits.email")] = "\tnew@x.com "
        values[.password] = "  hunter2  "

        // When
        let body = flow.makeBody(values: values, pressing: action)

        // Then the email-like fields are trimmed; the password keeps its (possibly meaningful) spaces
        #expect(body.fields["identifier"] == "user@x.com")
        #expect(body.fields["traits.email"] == "new@x.com")
        #expect(body.fields["password"] == "  hunter2  ")
    }
}
