import Foundation
import Testing
import OrySDK
@testable import OryClient

@Suite("SessionMapper")
struct SessionMapperTests {

    private func identityDTO(id: String = "identity-1", email: String = "a@b.com") -> OrySDKAPI.Identity {
        OrySDKAPI.Identity(
            id: id,
            schemaId: "default",
            schemaUrl: "https://example.com/s",
            traits: .dictionary(["email": .string(email)])
        )
    }

    @Test("collapses optional fields — absent active becomes false, absent AAL becomes unknown")
    func collapsesOptionals() {
        // Given a DTO with only the required id and an identity
        let dto = OrySDKAPI.Session(id: "s1", identity: identityDTO())

        // When
        let session = SessionMapper.flatMap(dto)

        // Then
        #expect(session.id == "s1")
        #expect(session.isActive == false)
        #expect(session.authenticatorAssuranceLevel == .unknown)
        #expect(session.identity?.id == "identity-1")
    }

    @Test("maps a known assurance level and decodes identity traits")
    func mapsAALAndTraits() throws {
        // Given
        let dto = OrySDKAPI.Session(
            active: true,
            authenticatorAssuranceLevel: .aal2,
            id: "s2",
            identity: identityDTO(id: "i2", email: "z@z.com")
        )

        // When
        let session = SessionMapper.flatMap(dto)

        // Then
        #expect(session.isActive)
        #expect(session.authenticatorAssuranceLevel == .aal2)

        struct Traits: Decodable { let email: String }
        let traits = try session.identity?.decodeTraits(as: Traits.self)
        #expect(traits?.email == "z@z.com")
    }

    @Test("maps an unknown assurance level to .unknown (forward-compatible)")
    func mapsUnknownAAL() {
        // Given a DTO with the generator's unknown-default enum case
        let dto = OrySDKAPI.Session(active: true, authenticatorAssuranceLevel: .unknownDefaultOpenApi, id: "s3")

        // When / Then
        let session = SessionMapper.flatMap(dto)
        #expect(session.authenticatorAssuranceLevel == .unknown)
    }
}
