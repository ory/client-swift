import Foundation
import Ory
import Testing

@Suite("OryNode")
struct OryNodeTests {

    @Test("Given an input node, when reading inputField, then it returns the node's field")
    func inputFieldOfInputNode() {
        // Given
        let field = OryInputField(name: .identifier, kind: .email)
        let node = OryNode(id: "identifier", group: .default, content: .input(field))

        // When
        let inputField = node.inputField

        // Then
        #expect(inputField == field)
    }

    @Test("Given a text, image or link node, when reading inputField, then it returns nil")
    func inputFieldOfOtherNodes() throws {
        // Given
        let message = OryUIMessage(id: 1050006, text: "SECRET", kind: .info)
        let url = try #require(URL(string: "https://acme.com"))
        let nodes = [
            OryNode(id: "totp_secret_key", group: .totp, content: .text(message)),
            OryNode(id: "totp_qr", group: .totp, content: .image(url: url)),
            OryNode(id: "continue", group: .default, content: .link(label: message, url: url)),
        ]

        // When
        let inputFields = nodes.map(\.inputField)

        // Then
        #expect(inputFields == [nil, nil, nil])
    }
}
