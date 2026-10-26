import Foundation
import OrySDK

/// Maps the generated SDK's ``OrySDK/UiText`` to a domain ``OryUIMessage``.
enum MessageMapper: Mapper {

    typealias Failure = Never

    static func map(_ input: OrySDKAPI.UiText) -> Result<OryUIMessage, Never> {
        .success(
            OryUIMessage(
                id: Int(input.id),
                text: input.text,
                kind: OryUIMessage.Kind(rawValue: input.type),
                context: context(input.context)
            )
        )
    }

    /// Kratos always sends `context` as an object; anything else carries no named values.
    static func context(_ value: JSONValue?) -> [String: OryJSONValue] {
        guard case let .dictionary(object)? = value else { return [:] }
        return object.mapValues(jsonValue)
    }

    private static func jsonValue(_ value: JSONValue) -> OryJSONValue {
        switch value {
        case let .string(string): .string(string)
        case let .int(int): .int(int)
        case let .double(double): .double(double)
        case let .bool(bool): .bool(bool)
        case let .array(array): .array(array.map(jsonValue))
        case let .dictionary(object): .object(object.mapValues(jsonValue))
        case .null: .null
        }
    }
}
