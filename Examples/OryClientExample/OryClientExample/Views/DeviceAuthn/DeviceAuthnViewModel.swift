import Foundation
import Observation
import OryClient
#if canImport(UIKit)
import UIKit
#endif

/// Drives the two-factor (device authentication) settings screen.
///
/// Every device operation is a single call on ``OryClientProtocol`` — the view model only
/// tracks whether this device is enrolled, reflects the session's assurance level, and
/// surfaces the result. Enrollment, step-up, and removal hide all of the Secure Enclave,
/// nonce, and attestation handling inside `OryClient`.
@MainActor
@Observable
final class DeviceAuthnViewModel {

    enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    /// Whether this device can do device authentication at all. Constant for the session.
    let isAvailable: Bool

    /// Whether this device can offer biometric (Face ID / Touch ID) enrollment. Constant for
    /// the session — it reflects the device's biometric capability, from
    /// ``OryClientProtocol/availableDeviceAuthenticationMethods``.
    let canUseBiometrics: Bool

    /// A user-facing name for the device's biometry, e.g. "Face ID", for button labels.
    let biometryLabel: String

    /// Every device enrolled on the account, for the "your devices" list. Refreshed after any
    /// change that adds or removes a key.
    private(set) var devices: [OryEnrolledDevice] = []

    private(set) var isEnrolled = false
    private(set) var isPINEnrolled = false
    private(set) var isBiometricEnrolled = false
    private(set) var isBusy = false
    private(set) var status: Status = .idle
    private(set) var assuranceLevel: OryAuthenticatorAssuranceLevel

    private let client: OryClientProtocol
    private let onSessionChanged: (OrySession) -> Void

    init(client: OryClientProtocol, session: OrySession, onSessionChanged: @escaping (OrySession) -> Void) {
        self.client = client
        self.isAvailable = client.isDeviceAuthenticationAvailable
        self.canUseBiometrics = client.availableDeviceAuthenticationMethods.contains(.biometric)
        self.biometryLabel = client.biometryType.label
        self.assuranceLevel = session.authenticatorAssuranceLevel
        self.onSessionChanged = onSessionChanged
    }

    /// Reads whether this device already has an enrolled key (and which kind), to pick the
    /// right actions.
    func load() async {
        // One read answers both "is this device enrolled?" and "with what protection?".
        let enrollment = (try? await client.deviceEnrollment()) ?? .notEnrolled
        switch enrollment {
        case .notEnrolled:
            isEnrolled = false
            isPINEnrolled = false
            isBiometricEnrolled = false
        case .enrolled(let verification):
            isEnrolled = true
            isPINEnrolled = verification == .pin
            isBiometricEnrolled = verification == .platform
        @unknown default:
            isEnrolled = false
            isPINEnrolled = false
            isBiometricEnrolled = false
        }
        await loadDevices()
    }

    /// Loads the account's enrolled devices. Best-effort: the screen's own actions stay usable
    /// when the list cannot be fetched (for example while offline), so a failure here is not
    /// surfaced as the screen's status.
    private func loadDevices() async {
        devices = (try? await client.enrolledDevices()) ?? []
    }

    /// Revokes another device — the "I lost my phone" action. Removing the entry that is this
    /// device behaves exactly like ``remove()``, so the screen reflects that too.
    func revoke(_ device: OryEnrolledDevice) async {
        await run {
            try await self.client.removeDevice(device)
            if device.isCurrentDevice {
                self.isEnrolled = false
                self.isPINEnrolled = false
                self.isBiometricEnrolled = false
            }
            devices.removeAll(where: { $0.id == device.id })
            if device.isCurrentDevice, let session = try? await self.client.currentSession() {
                self.assuranceLevel = session.authenticatorAssuranceLevel
                self.onSessionChanged(session)
            }
            self.status = .success("\(device.name) can no longer be used to sign in.")
            self.status = .success("\(device.name) can no longer be used to sign in.")
        }
    }

    /// Validates a chosen PIN against this app's policy before enrolling or resetting.
    /// `OryClient` performs no PIN validation — the server never sees the PIN — so this is where
    /// the integrating app enforces its own rules (see ``PINValidator``). Returns a user-facing
    /// error message, or `nil` when the PIN is acceptable.
    func pinValidationError(for pin: String) -> String? {
        PINValidator(pin: pin).execute().firstErrorMessage
    }

    func enroll() async {
        await run {
            try await self.client.enrollDevice(name: Self.deviceName)
            self.isEnrolled = true
            await self.loadDevices()
            // Enrolling adds a second factor but leaves the session at AAL1, so step up right
            // away to reach AAL2 instead of leaving the user below the required level.
            let authenticated = try await self.client.authenticateWithDevice()
            self.applySteppedUp(authenticated)
            self.status = .success("This device is now set up and verified for two-factor authentication.")
        }
    }

    func enrollWithPIN(_ pin: String) async {
        await run {
            try await self.client.enrollDevice(name: Self.deviceName, protection: .pin(pin))
            self.isEnrolled = true
            self.isPINEnrolled = true
            await self.loadDevices()

            // Enrolling adds a second factor but leaves the session at AAL1, so step up right
            // away with the PIN just entered — otherwise the user sits at AAL1 until a protected
            // request 403s.
            let authenticated = try await self.client.authenticateWithDevice(pin: pin)
            self.applySteppedUp(authenticated)
            self.status = .success("This device is set up and verified for two-factor sign-in.")
        }
    }

    /// Enrolls the device with biometrics (Face ID / Touch ID), then steps up right away — like
    /// PIN enrollment, adding a factor leaves the session at AAL1, so the identity now requires
    /// AAL2. `OryClient` prompts for biometrics during both calls.
    func enrollWithBiometrics() async {
        await run {
            try await self.client.enrollDevice(name: Self.deviceName, protection: .biometrics)
            self.isEnrolled = true
            self.isBiometricEnrolled = true
            await self.loadDevices()

            let authenticated = try await self.client.authenticateWithDevice()
            self.applySteppedUp(authenticated)
            self.status = .success("This device is set up and verified for \(self.biometryLabel) sign-in.")
        }
    }

    func stepUpWithBiometrics() async {
        await run {
            let authenticated = try await self.client.authenticateWithDevice()
            self.applySteppedUp(authenticated)
            self.status = .success("Stepped up to \(authenticated.session.authenticatorAssuranceLevel.rawValue).")
        }
    }

    /// Recovery for a forgotten or locked PIN: sets a new PIN without the old one. `OryClient`
    /// authenticates by device possession (a silent device-signature step-up), so no old PIN is
    /// needed; the recovery also steps the session up to AAL2.
    func resetPIN(_ newPin: String) async {
        await run {
            // Rotation is a settings change: it re-issues the PIN secret but does not touch the
            // session, so the assurance level on screen stays as it was. Whether the server
            // allows it from this session is its decision — a still-working PIN key makes the
            // project demand AAL2, which surfaces as `secondFactorRequired` below.
            try await self.client.resetDevicePIN(newPin: newPin)
            self.status = .success("Your PIN was reset. Use the new PIN to sign in on this device.")
        }
    }

    func stepUp() async {
        await run {
            let authenticated = try await self.client.authenticateWithDevice()
            self.applySteppedUp(authenticated)
            self.status = .success("Stepped up to \(authenticated.session.authenticatorAssuranceLevel.rawValue).")
        }
    }

    func stepUpWithPIN(_ pin: String) async {
        await run {
            let authenticated = try await self.client.authenticateWithDevice(pin: pin)
            self.applySteppedUp(authenticated)
            self.status = .success("Stepped up to \(authenticated.session.authenticatorAssuranceLevel.rawValue).")
        }
    }

    /// Reflects an upgraded (AAL2) session into the screen and up to the root, without setting a
    /// status message — each caller sets its own.
    private func applySteppedUp(_ authenticated: OryAuthenticatedSession) {
        assuranceLevel = authenticated.session.authenticatorAssuranceLevel
        onSessionChanged(authenticated.session)
    }

    func remove() async {
        await run {
            try await self.client.removeDevice()
            self.isEnrolled = false
            self.isPINEnrolled = false
            self.isBiometricEnrolled = false
            await self.loadDevices()
            // Refresh so the screen (and the root) reflect any assurance change.
            if let session = try? await self.client.currentSession() {
                self.assuranceLevel = session.authenticatorAssuranceLevel
                self.onSessionChanged(session)
            }
            self.status = .success("This device is no longer a second factor.")
        }
    }

    /// Local-only reset — useful when the device shows "enrolled" but verification fails
    /// (e.g. after a reinstall wiped the Secure Enclave key, or the credential was removed
    /// on another device). Does not touch the server credential.
    func forget() async {
        await run {
            try await self.client.forgetDevice()
            self.isEnrolled = false
            self.isPINEnrolled = false
            self.isBiometricEnrolled = false
            self.status = .success("This device's key was forgotten on this app.")
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        status = .idle
        defer { isBusy = false }
        do {
            try await operation()
        } catch OryClientError.secondFactorRequired {
            // The change needs AAL2 and the session does not have it. Nothing is wrong with the
            // credentials — prompt for the PIN and step up, then let the user try again.
            status = .failure("Enter your current PIN to verify this device, then try again.")
        } catch OryClientError.reauthenticationRequired {
            // The session is valid but older than the project's privileged window. A real app
            // would re-prompt for the password (or the PIN) here rather than sign the user out.
            status = .failure("For your security, please confirm it's you before changing this.")
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "My device"
        #endif
    }
}

extension OryBiometryType {
    /// A user-facing name for button labels and prompts.
    var label: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Biometrics"
        }
    }

    /// An SF Symbol matching the biometry, for buttons.
    var systemImage: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "person.badge.key"
        }
    }
}

#if DEBUG
extension DeviceAuthnViewModel {
    /// A view-only fixture: `.task` loads the enrollment state from the configured client.
    static func preview(
        available: Bool = true,
        methods: Set<OryDeviceAuthenticationMethod> = [.pin, .biometric],
        enrollment: OryDeviceEnrollmentState = .notEnrolled,
        aal: OryAuthenticatorAssuranceLevel = .aal1
    ) -> DeviceAuthnViewModel {
        var client = PreviewOryClient()
        client.isDeviceAuthenticationAvailable = available
        client.availableDeviceAuthenticationMethods = methods
        client.deviceEnrollmentState = enrollment
        return DeviceAuthnViewModel(client: client, session: PreviewData.session(aal: aal), onSessionChanged: { _ in })
    }
}
#endif
