import Foundation
import Testing
import OryClientTestDoubles
@testable import OryClient

@Suite("OryClient device list")
struct OryClientDeviceListTests {

    private func record(
        id: String,
        name: String = "iPhone",
        state: String = "confirmed",
        userVerification: String = "pin",
        deviceType: String = "iOS"
    ) -> DeviceKeyRecord {
        DeviceKeyRecord(
            clientKeyID: id,
            deviceName: name,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            deviceType: deviceType,
            state: state,
            userVerification: userVerification
        )
    }

    private func makeClient(
        records: [DeviceKeyRecord],
        storedKeyID: String? = nil
    ) -> (OryClient, FakeFrontendRepository, InMemoryDeviceKeyStore) {
        let keyStore = storedKeyID.map {
            InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(clientKeyID: $0, localKeyID: "apple", userVerification: .pin))
        } ?? InMemoryDeviceKeyStore()
        let frontend = FakeFrontendRepository(deviceKeyRecords: records)
        let client = OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st"),
            frontend: frontend,
            deviceAuthn: frontend,
            deviceKeyStore: keyStore
        )
        return (client, frontend, keyStore)
    }

    @Test("lists the identity's devices and marks the one this app runs on")
    func listsDevicesAndMarksCurrent() async throws {
        let (client, _, _) = makeClient(
            records: [record(id: "other", name: "Old iPhone"), record(id: "mine", name: "My iPhone")],
            storedKeyID: "mine"
        )

        let devices = try await client.enrolledDevices()

        #expect(devices.map(\.clientKeyID) == ["other", "mine"])
        #expect(devices.first { $0.isCurrentDevice }?.name == "My iPhone")
        #expect(devices.filter(\.isCurrentDevice).count == 1)
    }

    @Test("a device with no local key still sees the identity's other devices")
    func listsWithoutALocalKey() async throws {
        // A freshly reinstalled app has no key, but the user still needs to see — and clean
        // up — the keys previous installs left behind.
        let (client, _, _) = makeClient(records: [record(id: "orphan")], storedKeyID: nil)

        let devices = try await client.enrolledDevices()

        #expect(devices.count == 1)
        #expect(devices[0].isCurrentDevice == false)
    }

    @Test("a locked device is reported as locked")
    func reportsLockedDevices() async throws {
        let (client, _, _) = makeClient(records: [record(id: "a"), record(id: "b", state: "locked")])

        let devices = try await client.enrolledDevices()

        #expect(devices[0].isLocked == false)
        #expect(devices[1].isLocked)
    }

    @Test("a platform or state this build does not know does not hide the device")
    func tolerartesUnknownValues() async throws {
        let (client, _, _) = makeClient(
            records: [record(id: "x", state: "quarantined", userVerification: "retina", deviceType: "Fuchsia")]
        )

        let devices = try await client.enrolledDevices()

        #expect(devices.count == 1)
        #expect(devices[0].platform == .unknown("Fuchsia"))
        // An unrecognized verification degrades to the weakest reading rather than claiming a
        // protection the client cannot describe, and an unknown state is not "locked".
        #expect(devices[0].userVerification == OryDeviceUserVerification.none)
        #expect(devices[0].isLocked == false)
    }

    @Test("removing another device leaves this device's key in place")
    func removingAnotherDeviceKeepsTheLocalKey() async throws {
        let (client, frontend, keyStore) = makeClient(
            records: [record(id: "lost"), record(id: "mine")],
            storedKeyID: "mine"
        )
        let lost = try #require(try await client.enrolledDevices().first { $0.clientKeyID == "lost" })

        try await client.removeDevice(lost)

        #expect(await frontend.submittedClientKeyID == "lost")
        #expect(await keyStore.stored?.clientKeyID == "mine")
    }

    @Test("removing the current device through the list also clears the local key")
    func removingCurrentDeviceClearsTheLocalKey() async throws {
        // Same effect as removeDevice(): this device stops being enrolled, so the stale record
        // must not linger and read as an enrollment.
        let (client, frontend, keyStore) = makeClient(records: [record(id: "mine")], storedKeyID: "mine")
        let mine = try #require(try await client.enrolledDevices().first)

        try await client.removeDevice(mine)

        #expect(await frontend.submittedClientKeyID == "mine")
        #expect(await keyStore.stored == nil)
    }

    @Test("a PIN key keeps the server's demand for a second factor")
    func removalOfAPINKeySurfacesTheServersDemand() async throws {
        // The client cannot step a PIN key up without its PIN, so inventing an error here
        // would hide the one instruction the caller can act on.
        let keyStore = InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(
            clientKeyID: "mine",
            localKeyID: "apple",
            pinSecret: try DevicePINVault(sealingKeyProvider: InsecureEphemeralPINSealingKeyProvider())
                .protect(pinSecret: Data(repeating: 1, count: 32), pinString: "0000"),
            userVerification: .pin
        ))
        let frontend = FakeFrontendRepository(
            removalFlow: .failure(.secondFactorRequired),
            deviceKeyRecords: [record(id: "mine")]
        )
        let client = OryClient(
            storage: InMemorySessionStorage(initialToken: "ory_st"),
            frontend: frontend,
            deviceAuthn: frontend,
            deviceKeyStore: keyStore
        )

        await #expect {
            try await client.removeDevice()
        } throws: { error in
            guard case OryClientError.secondFactorRequired = error else { return false }
            return true
        }

        // And the local key survives a refused removal.
        #expect(await keyStore.stored != nil)
    }

    @Test("enrolledDevices without a session throws notAuthenticated")
    func listRequiresASession() async throws {
        let frontend = FakeFrontendRepository(deviceKeyRecords: [record(id: "a")])
        let client = OryClient(storage: InMemorySessionStorage(), frontend: frontend, deviceAuthn: frontend)

        await #expect {
            _ = try await client.enrolledDevices()
        } throws: { error in
            guard case OryClientError.notAuthenticated = error else { return false }
            return true
        }
    }
}
