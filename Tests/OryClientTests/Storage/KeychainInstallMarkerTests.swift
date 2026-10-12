import Foundation
import Testing
@testable import OryClient

@Suite("KeychainInstallMarker")
struct KeychainInstallMarkerTests {

    /// A defaults suite of its own per test, so the marker never leaks between them or into
    /// the host's real defaults.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ory.tests.\(UUID().uuidString)")!
    }

    @Test("clears once on a fresh install, then never again")
    func clearsOnceThenMarks() {
        let defaults = makeDefaults()
        var clearCount = 0
        let clear = { clearCount += 1; return errSecSuccess }

        KeychainInstallMarker.clearStaleStateOnFreshInstall(markerKey: "m", accessGroup: nil, defaults: defaults, clear: clear)
        KeychainInstallMarker.clearStaleStateOnFreshInstall(markerKey: "m", accessGroup: nil, defaults: defaults, clear: clear)

        #expect(clearCount == 1)
    }

    @Test("never clears state shared through an access group")
    func skipsWhenSharedThroughAnAccessGroup() {
        // An app extension has its own empty container, so it would read "fresh install" on
        // first launch and destroy the live key the host app enrolled.
        let defaults = makeDefaults()
        var clearCount = 0

        KeychainInstallMarker.clearStaleStateOnFreshInstall(
            markerKey: "m",
            accessGroup: "group.com.acme.shared",
            defaults: defaults
        ) { clearCount += 1; return errSecSuccess }

        #expect(clearCount == 0)
        #expect(defaults.bool(forKey: "m") == false)
    }

    @Test("a Keychain that was unavailable is retried on the next launch")
    func retriesWhenTheKeychainFails() {
        // Reading the Keychain can fail at launch (a locked device, for example). Marking the
        // install as handled anyway would leave the stale state behind permanently.
        let defaults = makeDefaults()
        var clearCount = 0

        KeychainInstallMarker.clearStaleStateOnFreshInstall(markerKey: "m", accessGroup: nil, defaults: defaults) {
            clearCount += 1
            return errSecInteractionNotAllowed
        }
        KeychainInstallMarker.clearStaleStateOnFreshInstall(markerKey: "m", accessGroup: nil, defaults: defaults) {
            clearCount += 1
            return errSecSuccess
        }

        #expect(clearCount == 2)
        #expect(defaults.bool(forKey: "m"))
    }

    @Test("nothing to delete still counts as handled")
    func treatsNotFoundAsSuccess() {
        let defaults = makeDefaults()

        KeychainInstallMarker.clearStaleStateOnFreshInstall(markerKey: "m", accessGroup: nil, defaults: defaults) {
            errSecItemNotFound
        }

        #expect(defaults.bool(forKey: "m"))
    }
}
