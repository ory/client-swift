import Foundation
import Testing
@testable import OryClient

@Suite("OryStoredDeviceKey")
struct StoredDeviceKeyTests {

    @Test("a record without an owner does not decode")
    func rejectsRecordWithoutOwner() {
        let older = Data(#"""
        {"schemaVersion":1,"clientKeyID":"srv","localKeyID":"apple","userVerification":"pin"}
        """#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(OryStoredDeviceKey.self, from: older)
        }
    }

    @Test("a round trip preserves the version")
    func roundTrip() throws {
        let key = OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .pin, identityID: "identity-1")

        let decoded = try JSONDecoder().decode(
            OryStoredDeviceKey.self,
            from: try JSONEncoder().encode(key)
        )

        #expect(decoded == key)
        #expect(decoded.schemaVersion == OryStoredDeviceKey.currentSchemaVersion)
    }
}
