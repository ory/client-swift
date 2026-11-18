import Foundation
import Security

/// Detects a fresh install so state the previous install left in the Keychain can be cleared.
///
/// Keychain items survive app deletion; the app container does not. `UserDefaults` therefore
/// answers "has this install run before?", and a missing marker means the Keychain holds state
/// belonging to an install that is gone — a device key whose Secure Enclave key was destroyed
/// with the app, and a session token nobody signed in for.
///
/// The marker lives in the app's own container, so it can only speak for the app that wrote it.
/// That is why cleanup is skipped entirely when the caller shares state through a Keychain
/// access group: a second process (an app extension, or another app in the group) has its own
/// empty `UserDefaults` and would read "fresh install" on its first launch, destroying a live
/// enrollment it did not create. When state is shared, its lifecycle is the app's to manage.
enum KeychainInstallMarker {

    /// Runs `clear` once per install, unless state is shared through an access group.
    ///
    /// The marker is persisted only after `clear` reports success, so a Keychain that was
    /// unavailable at launch (for example on a locked device) is retried next time instead of
    /// leaving stale state behind for good.
    static func clearStaleStateOnFreshInstall(
        markerKey: String,
        accessGroup: String?,
        defaults: UserDefaults = .standard,
        clear: () -> OSStatus
    ) {
        guard accessGroup == nil else { return }
        guard !defaults.bool(forKey: markerKey) else { return }

        let status = clear()
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        defaults.set(true, forKey: markerKey)
    }
}
