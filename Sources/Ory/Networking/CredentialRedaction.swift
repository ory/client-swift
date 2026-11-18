import Foundation

/// Replaces credential values in a JSON body with a placeholder. The client hands interceptors
/// these redacted copies and keeps the original for the wire and for decoding.
enum CredentialRedaction {

    static let placeholder = "[REDACTED]"

    /// Matched as substrings of lowercased names, so a credential field this build has never
    /// seen is still caught when its name follows Ory's naming (`password`, `code`, `pin_proof`,
    /// `session_token`, `lookup_secret`, `signature`, …).
    private static let sensitiveNameFragments = ["password", "secret", "token", "proof", "code", "signature"]

    /// The TOTP provisioning QR encodes the secret but its name matches no fragment.
    private static let sensitiveNodeIdentifiers: Set = ["totp_qr"]

    /// The fields in which a flow node carries its content: an input's `value`, a text node's
    /// `text`, and an image node's `src`.
    private static let nodeContentKeys: Set = ["value", "text", "src"]

    /// Returns `body` with every sensitive value replaced. A body that is not JSON is returned
    /// unchanged; a JSON body that cannot be written back is dropped rather than passed on
    /// unredacted.
    static func redact(_ body: Data?) -> Data? {
        guard let body, !body.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        else {
            return body
        }
        return try? JSONSerialization.data(withJSONObject: redactValue(json), options: [.fragmentsAllowed, .sortedKeys])
    }

    private static func redactValue(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            // A flow node names itself in `name` (inputs) or `id` (text and image nodes).
            let describesCredential = ["name", "id"].contains { key in
                (object[key] as? String).map { isSensitive($0) || sensitiveNodeIdentifiers.contains($0) } ?? false
            }
            var result: [String: Any] = [:]
            for (key, child) in object {
                if isSensitive(key) {
                    result[key] = placeholder
                } else if describesCredential && nodeContentKeys.contains(key) {
                    result[key] = key == "text" ? redactMessageText(child) : placeholder
                } else {
                    result[key] = redactValue(child)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(redactValue)
        }
        return value
    }

    /// A text node's content is a message object, so only its `text` is replaced and the
    /// message ID and type stay readable.
    private static func redactMessageText(_ content: Any) -> Any {
        guard var message = content as? [String: Any] else { return placeholder }
        message["text"] = placeholder
        return redactValue(message)
    }

    private static func isSensitive(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return sensitiveNameFragments.contains { lowered.contains($0) }
    }
}
