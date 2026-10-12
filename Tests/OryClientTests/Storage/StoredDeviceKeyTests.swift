import Foundation
import Testing
@testable import OryClient

@Suite("OryStoredDeviceKey")
struct StoredDeviceKeyTests {

    @Test("a record written before versioning existed still decodes")
    func decodesUnversionedRecord() throws {
        // Every device enrolled before the schema version was introduced has a record without
        // the field. Failing to read those would silently un-enroll the whole installed base.
        let legacy = Data(#"""
        {"clientKeyID":"srv","localKeyID":"apple","userVerification":"pin"}
        """#.utf8)

        let key = try JSONDecoder().decode(OryStoredDeviceKey.self, from: legacy)

        #expect(key.schemaVersion == OryStoredDeviceKey.currentSchemaVersion)
        #expect(key.clientKeyID == "srv")
    }

    @Test("a round trip preserves the version")
    func roundTrip() throws {
        let key = OryStoredDeviceKey(clientKeyID: "srv", localKeyID: "apple", userVerification: .pin)

        let decoded = try JSONDecoder().decode(
            OryStoredDeviceKey.self,
            from: try JSONEncoder().encode(key)
        )

        #expect(decoded == key)
        #expect(decoded.schemaVersion == 1)
    }
}
