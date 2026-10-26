import Foundation
import Testing
@testable import OryClient

@Suite("Credential redaction")
struct CredentialRedactionTests {

    private func redacted(_ json: String) throws -> Any {
        let data = try #require(CredentialRedaction.redact(Data(json.utf8)))
        return try JSONSerialization.jsonObject(with: data)
    }

    @Test("Credential fields are replaced and other fields are kept")
    func redactsCredentialFields() throws {
        // Given a body with credentials next to ordinary fields
        let body = #"{"password":"hunter2","code":"123456","pin_proof":"cHJvb2Y=","session_token":"ory_st_x","csrf_token":"c","identifier":"alice@example.com","method":"password"}"#

        // When it is redacted
        let result = try #require(try redacted(body) as? [String: String])

        // Then only the credentials are replaced
        for key in ["password", "code", "pin_proof", "session_token", "csrf_token"] {
            #expect(result[key] == CredentialRedaction.placeholder)
        }
        #expect(result["identifier"] == "alice@example.com")
        #expect(result["method"] == "password")
    }

    @Test("Nested objects, arrays, and a credential value inside a flow node are redacted")
    func redactsNestedValuesAndNodeValues() throws {
        // Given a body with a token inside an array and a code node that echoes the entered value
        let body = #"{"continue_with":[{"action":"set_ory_session_token","ory_session_token":"ory_st_x"}],"ui":{"nodes":[{"attributes":{"name":"code","value":"123456"}},{"attributes":{"name":"identifier","value":"alice@example.com"}}]}}"#

        // When it is redacted
        let result = try #require(try redacted(body) as? [String: Any])

        // Then the token in the array and the code node's value are replaced, the identifier is kept
        let continueWith = try #require(result["continue_with"] as? [[String: Any]])
        #expect(continueWith.first?["ory_session_token"] as? String == CredentialRedaction.placeholder)
        #expect(continueWith.first?["action"] as? String == "set_ory_session_token")
        let ui = try #require(result["ui"] as? [String: Any])
        let nodes = try #require(ui["nodes"] as? [[String: Any]])
        let values = nodes.compactMap { ($0["attributes"] as? [String: Any])?["value"] as? String }
        #expect(values == [CredentialRedaction.placeholder, "alice@example.com"])
    }

    @Test("A device login assertion is redacted")
    func redactsDeviceLoginSignature() throws {
        // Given a device login body with the App Attest assertion and the PIN proof
        let body = #"{"method":"deviceauthn","signature":"assertion","pin_proof":"proof","client_key_id":"key-1"}"#

        // When it is redacted
        let result = try #require(try redacted(body) as? [String: String])

        // Then both credentials are replaced and the key id is kept
        #expect(result["signature"] == CredentialRedaction.placeholder)
        #expect(result["pin_proof"] == CredentialRedaction.placeholder)
        #expect(result["method"] == "deviceauthn")
        #expect(result["client_key_id"] == "key-1")
    }

    @Test("TOTP setup and backup code display nodes are redacted, other display nodes are kept")
    func redactsCredentialDisplayNodes() throws {
        // Given settings nodes in the shapes Kratos sends: the TOTP secret and the backup codes as
        // text nodes, the TOTP provisioning QR as an image node, and an ordinary text node
        let body = #"""
        {"ui":{"nodes":[
          {"type":"text","group":"totp","attributes":{"node_type":"text","id":"totp_secret_key","text":{"id":1050006,"text":"JBSWY3DPEHPK3PXP","type":"info","context":{"secret":"JBSWY3DPEHPK3PXP"}}}},
          {"type":"img","group":"totp","attributes":{"node_type":"img","id":"totp_qr","src":"data:image/png;base64,iVBORw0KGgo=","width":256,"height":256}},
          {"type":"text","group":"lookup_secret","attributes":{"node_type":"text","id":"lookup_secret_codes","text":{"id":1050015,"text":"abcd1234, efgh5678","type":"info","context":{"secrets":[{"id":1050009,"text":"abcd1234","type":"info","context":{"secret":"abcd1234"}}]}}}},
          {"type":"text","group":"default","attributes":{"node_type":"text","id":"welcome","text":{"id":1,"text":"Welcome","type":"info"}}}
        ]}}
        """#

        // When it is redacted
        let result = try #require(try redacted(body) as? [String: Any])

        // Then the secret, the QR source, and the codes are replaced, and the plain text is kept
        let ui = try #require(result["ui"] as? [String: Any])
        let attributes = try #require(ui["nodes"] as? [[String: Any]]).compactMap { $0["attributes"] as? [String: Any] }
        let text = { (index: Int) in (attributes[index]["text"] as? [String: Any])?["text"] as? String }
        #expect(text(0) == CredentialRedaction.placeholder)
        #expect(attributes[1]["src"] as? String == CredentialRedaction.placeholder)
        #expect(attributes[1]["width"] as? Int == 256)
        #expect(text(2) == CredentialRedaction.placeholder)
        #expect(text(3) == "Welcome")
        let serialized = try #require(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8))
        for secret in ["JBSWY3DPEHPK3PXP", "iVBORw0KGgo", "abcd1234", "efgh5678"] {
            #expect(!serialized.contains(secret))
        }
    }

    @Test("A body that is not JSON passes through unchanged")
    func passesNonJSONThrough() {
        let html = Data("<html>Bad gateway</html>".utf8)

        #expect(CredentialRedaction.redact(html) == html)
        #expect(CredentialRedaction.redact(nil) == nil)
    }
}
