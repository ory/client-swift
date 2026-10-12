import Foundation
import Testing
@testable import OryClient

@Suite("ErrorMapper.messages")
struct ErrorMapperTests {

    @Test("parses UI messages from a flow error body")
    func flowMessages() {
        // When
        let messages = ErrorMapper.messages(from: Fixture.errorFlow)

        // Then
        #expect(messages.count == 1)
        #expect(messages.first?.id == 4000006)
        #expect(messages.first?.text == "Invalid credentials")
        #expect(messages.first?.kind == .error)
    }

    @Test("parses a generic error body")
    func genericMessage() {
        // When
        let messages = ErrorMapper.messages(from: Fixture.errorGeneric)

        // Then
        #expect(messages.first?.text == "No active session")
        #expect(messages.first?.kind == .error)
    }

    @Test("returns empty for nil or unrecognized bodies")
    func emptyForUnrecognized() {
        #expect(ErrorMapper.messages(from: nil).isEmpty)
        #expect(ErrorMapper.messages(from: Data("{}".utf8)).isEmpty)
        #expect(ErrorMapper.messages(from: Data("not json".utf8)).isEmpty)
    }

    @Test("carries the message context from a flow error body")
    func flowMessageContext() {
        // Given a validation message whose text was filled from named values
        let body = Data(#"{"ui":{"messages":[{"id":4000003,"text":"length must be >= 8, but got 3","type":"error","context":{"min_length":8,"actual_length":3}}]}}"#.utf8)

        // When
        let messages = ErrorMapper.messages(from: body)

        // Then
        #expect(messages.first?.context == ["min_length": .int(8), "actual_length": .int(3)])
    }

    @Test("a message type this build does not know still decodes")
    func unknownMessageType() {
        // Given messages with a future type and with no type at all
        let body = Data(#"{"ui":{"messages":[{"id":1,"text":"a","type":"warning"},{"id":2,"text":"b"}]}}"#.utf8)

        // When
        let messages = ErrorMapper.messages(from: body)

        // Then the server's name is kept when there is one
        #expect(messages.map(\.kind) == [OryUIMessage.Kind(rawValue: "warning"), .unknown])
        #expect(messages.allSatisfy { $0.context.isEmpty })
    }
}

@Suite("ErrorMapper.envelope")
struct ErrorEnvelopeTests {

    @Test("keeps the machine-readable error id as a string")
    func parsesErrorID() {
        // Ory error ids are strings ("session_inactive"); reading them as integers loses the
        // only stable discriminator the body carries.
        let envelope = ErrorMapper.envelope(from: Fixture.errorGeneric)

        #expect(envelope.id == .sessionInactive)
        #expect(envelope.messages.first?.text == "No active session")
    }

    @Test("an id this build does not know still decodes")
    func parsesUnknownErrorID() {
        // Ory adds error ids over time. An app built before one existed must still be able to
        // see and log it, rather than dropping it on the floor.
        let body = Data(#"{"error":{"id":"some_future_condition","message":"…"}}"#.utf8)

        let envelope = ErrorMapper.envelope(from: body)

        #expect(envelope.id == OryErrorID(rawValue: "some_future_condition"))
    }

    @Test("reads the replacement flow id out of an expired-flow body")
    func parsesUseFlowID() {
        // A 410 names the flow the server already created to replace the expired one.
        let envelope = ErrorMapper.envelope(from: Fixture.errorFlowExpired)

        #expect(envelope.id == .selfServiceFlowExpired)
        #expect(envelope.useFlowID == "a7f0b3d4-1f6b-4e2c-9d5a-8c1e2b3f4a5d")
    }

    @Test("a flow body carries its UI messages and no error id")
    func parsesFlowBody() {
        let envelope = ErrorMapper.envelope(from: Fixture.errorFlow)

        #expect(envelope.id == nil)
        #expect(envelope.messages.first?.id == 4000006)
    }

    @Test("an unreadable body yields an empty envelope")
    func emptyEnvelope() {
        #expect(ErrorMapper.envelope(from: nil).id == nil)
        #expect(ErrorMapper.envelope(from: Data("not json".utf8)).messages.isEmpty)
    }
}
