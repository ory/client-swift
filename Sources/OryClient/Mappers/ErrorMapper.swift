import Foundation
import OrySDK

/// Everything an Ory error body says, in the form the client acts on.
struct OryErrorEnvelope {

    /// The machine-readable `error.id`. Absent on flow bodies, which say what went wrong
    /// through their UI messages instead.
    let id: OryErrorID?

    /// User-facing text, from `ui.messages` on a flow body or `error.message` on a generic one.
    let messages: [OryUIMessage]

    /// On an expired flow, the id of the replacement flow the server has already created.
    let useFlowID: String?

    static let empty = OryErrorEnvelope(id: nil, messages: [], useFlowID: nil)
}

/// Parses user-facing messages out of an Ory error body.
///
/// The transport (``HTTPClient``) and data source use this to populate
/// ``OryClientError/server(status:id:messages:)``, so error responses carry the
/// localized text Ory returns.
enum ErrorMapper {

    /// Extracts user-facing messages from an Ory error body.
    ///
    /// Handles both flow bodies (`{"ui":{"messages":[…]}}`) and generic error bodies
    /// (`{"error":{"message":"…"}}`). Returns an empty array when neither is present.
    static func messages(from data: Data?) -> [OryUIMessage] {
        guard let data else { return [] }

        let decoder = JSONDecoder()

        if let flow = try? decoder.decode(FlowErrorBody.self, from: data),
           let uiMessages = flow.ui?.messages, !uiMessages.isEmpty {
            return uiMessages.map(OryUIMessage.init(body:))
        }

        if let generic = try? decoder.decode(GenericErrorBody.self, from: data),
           let message = generic.error?.message {
            // A generic body has no numeric message id — `error.id` is a string, carried by
            // ``OryErrorEnvelope/id`` instead — so this text is all the message can offer.
            return [OryUIMessage(id: 0, text: message, kind: .error)]
        }

        return []
    }

    /// Parses everything the client needs out of an Ory error body: the machine-readable
    /// `error.id`, the user-facing messages, and the replacement flow id an expired flow names.
    static func envelope(from data: Data?) -> OryErrorEnvelope {
        guard let data else { return .empty }

        let generic = try? JSONDecoder().decode(GenericErrorBody.self, from: data)
        return OryErrorEnvelope(
            id: generic?.error?.id.map(OryErrorID.init(rawValue:)),
            messages: messages(from: data),
            useFlowID: generic?.useFlowID
        )
    }
}

// MARK: - Wire shapes

/// The subset of a flow body that carries UI messages.
private struct FlowErrorBody: Decodable {
    let ui: UI?

    struct UI: Decodable {
        let messages: [Message]?
    }

    struct Message: Decodable {
        let id: Int
        let text: String
        let type: String?
        let context: JSONValue?
    }
}

/// The subset of a generic Ory error body. An expired flow adds `use_flow_id` alongside the
/// error object, naming the flow the server created to replace the expired one.
private struct GenericErrorBody: Decodable {
    let error: Inner?
    let useFlowID: String?

    enum CodingKeys: String, CodingKey {
        case error
        case useFlowID = "use_flow_id"
    }

    struct Inner: Decodable {
        let id: String?
        let message: String?
    }
}

private extension OryUIMessage {
    init(body: FlowErrorBody.Message) {
        self.init(
            id: body.id,
            text: body.text,
            kind: body.type.map(OryUIMessage.Kind.init(rawValue:)) ?? .unknown,
            context: MessageMapper.context(body.context)
        )
    }
}
