import Foundation
import OrySDK
import Testing
@testable import OryClient

@Suite("MessageMapper")
struct MessageMapperTests {

    @Test("maps the message context, including nested values")
    func mapsContext() {
        // Given
        let text = OrySDKAPI.UiText(
            context: .dictionary([
                "min_length": .int(8),
                "ratio": .double(0.5),
                "reason": .string("too short"),
                "strict": .bool(true),
                "providers": .array([.string("google")]),
                "nested": .dictionary(["missing": .null]),
            ]),
            id: 4_000_003,
            text: "length must be >= 8, but got 3",
            type: "error"
        )

        // When
        let message = MessageMapper.flatMap(text)

        // Then
        #expect(message.kind == .error)
        #expect(message.context == [
            "min_length": .int(8),
            "ratio": .double(0.5),
            "reason": .string("too short"),
            "strict": .bool(true),
            "providers": .array([.string("google")]),
            "nested": .object(["missing": .null]),
        ])
    }

    @Test("a missing or non-object context maps to an empty one")
    func emptyContext() {
        // Given
        let absent = OrySDKAPI.UiText(id: 1, text: "a", type: "info")
        let scalar = OrySDKAPI.UiText(context: .string("x"), id: 2, text: "b", type: "info")

        // When / Then
        #expect(MessageMapper.flatMap(absent).context.isEmpty)
        #expect(MessageMapper.flatMap(scalar).context.isEmpty)
    }

    @Test("a message type this build does not know keeps its wire name")
    func unknownKind() {
        // Given
        let text = OrySDKAPI.UiText(id: 1, text: "a", type: "warning")

        // When / Then
        #expect(MessageMapper.flatMap(text).kind == OryUIMessage.Kind(rawValue: "warning"))
    }
}
