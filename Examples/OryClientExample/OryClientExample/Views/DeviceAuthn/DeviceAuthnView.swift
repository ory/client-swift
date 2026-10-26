import OryClient
import SwiftUI

struct DeviceAuthnView: View {

    @State private var viewModel: DeviceAuthnViewModel
    @State private var showPINSetup = false
    @State private var showPINReset = false
    @State private var showPINVerify = false
    @State private var pinError: String?

    init(viewModel: DeviceAuthnViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.isAvailable {
                statusSection
                actionsSection
                devicesSection
                resultSection
            } else {
                unavailableSection
            }
        }
        .navigationTitle("Two-factor authentication")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showPINSetup) {
            PINEntryView(
                title: "Choose a PIN",
                prompt: "Set a PIN to sign in without a password on this device.",
                actionTitle: "Set up",
                errorMessage: pinError,
                onSubmit: { pin in submitPIN(pin, showing: $showPINSetup) { await viewModel.enrollWithPIN($0) } },
                onCancel: { dismissPINSheet($showPINSetup) }
            )
        }
        .sheet(isPresented: $showPINReset) {
            PINEntryView(
                title: "Reset your PIN",
                prompt: "Set a new PIN for this device. You don't need your old one.",
                actionTitle: "Reset PIN",
                errorMessage: pinError,
                onSubmit: { pin in submitPIN(pin, showing: $showPINReset) { await viewModel.resetPIN($0) } },
                onCancel: { dismissPINSheet($showPINReset) }
            )
        }
        .sheet(isPresented: $showPINVerify) {
            PINEntryView(
                title: "Verify it's you",
                prompt: "Enter your PIN to step this device up to AAL2.",
                actionTitle: "Verify",
                onSubmit: { pin in
                    showPINVerify = false
                    Task { await viewModel.stepUpWithPIN(pin) }
                },
                onCancel: { showPINVerify = false }
            )
        }
    }

    /// Enforces the app's PIN policy before handing the PIN to `OryClient`: on failure it shows
    /// the message inline and keeps the sheet open; on success it dismisses and runs `action`.
    /// `OryClient` itself accepts any PIN, so this gate is the app's responsibility.
    private func submitPIN(_ pin: String, showing sheet: Binding<Bool>, action: @escaping (String) async -> Void) {
        if let error = viewModel.pinValidationError(for: pin) {
            pinError = error
            return
        }
        pinError = nil
        sheet.wrappedValue = false
        Task { await action(pin) }
    }

    private func dismissPINSheet(_ sheet: Binding<Bool>) {
        pinError = nil
        sheet.wrappedValue = false
    }

    /// The account's enrolled devices, with a swipe action to revoke one — the "I lost my
    /// phone" flow. `OryClient` marks the entry the app is running on, which is what makes it
    /// safe to warn before revoking the current device.
    @ViewBuilder
    private var devicesSection: some View {
        if !viewModel.devices.isEmpty {
            Section("Your devices") {
                ForEach(viewModel.devices) { device in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.isCurrentDevice ? "\(device.name) (this device)" : device.name)
                        Text(device.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Revoke", role: .destructive) {
                            Task { await viewModel.revoke(device) }
                        }
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Assurance level", value: viewModel.assuranceLevel.rawValue)
            LabeledContent("This device", value: viewModel.isEnrolled
                ? "Enrolled"
                : viewModel.isEnrolledForAnotherAccount ? "Set up for another account" : "Not enrolled")
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if viewModel.isEnrolled {
                Button("Verify with this device") {
                    if viewModel.isPINEnrolled {
                        pinError = nil
                        showPINVerify = true
                    } else if viewModel.isBiometricEnrolled {
                        Task { await viewModel.stepUpWithBiometrics() }
                    } else {
                        Task { await viewModel.stepUp() }
                    }
                }
                if viewModel.isPINEnrolled {
                    Button("Reset PIN") {
                        pinError = nil
                        showPINReset = true
                    }
                }
                Button("Remove this device", role: .destructive) {
                    Task { await viewModel.remove() }
                }
                Button("Forget on this app only") {
                    Task { await viewModel.forget() }
                }
            } else if viewModel.isEnrolledForAnotherAccount {
                // Taking the device over ends device sign-in for the other account on this phone.
                Button("Use this device for my account") {
                    Task { await viewModel.forget() }
                }
            } else {
                Button("Set up this device") {
                    Task { await viewModel.enroll() }
                }
                Button("Set up with PIN (passwordless)") {
                    pinError = nil
                    showPINSetup = true
                }
                if viewModel.canUseBiometrics {
                    Button("Set up with \(viewModel.biometryLabel) (passwordless)") {
                        Task { await viewModel.enrollWithBiometrics() }
                    }
                }
            }
        } footer: {
            if viewModel.isEnrolled {
                Text("Verifying steps the session up to AAL2 using the key bound to this device.")
            } else {
                Text("“Set up this device” adds a second factor. “Set up with PIN” or “Set up with \(viewModel.biometryLabel)” also lets you sign in without a password on this device.")
            }
        }
        .disabled(viewModel.isBusy)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.status {
        case .idle:
            if viewModel.isBusy {
                Section { ProgressView() }
            }
        case let .success(message):
            Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) }
        case let .failure(message):
            Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        }
    }

    private var unavailableSection: some View {
        Section {
            Label("Not available on this device", systemImage: "exclamationmark.triangle")
        } footer: {
            Text("Device authentication needs a physical device with a Secure Enclave. On the Simulator, run a build that injects a relaxed authenticator.")
        }
    }
}

#if DEBUG
#Preview("Not enrolled") {
    NavigationStack { DeviceAuthnView(viewModel: .preview()) }
}

#Preview("PIN enrolled") {
    NavigationStack { DeviceAuthnView(viewModel: .preview(enrollment: .enrolled(.pin), aal: .aal2)) }
}

#Preview("Biometric enrolled") {
    NavigationStack { DeviceAuthnView(viewModel: .preview(enrollment: .enrolled(.platform), aal: .aal2)) }
}

#Preview("Unavailable") {
    NavigationStack { DeviceAuthnView(viewModel: .preview(available: false, methods: [])) }
}
#endif

private extension OryEnrolledDevice {
    /// A one-line summary of how the device verifies its holder and when it was enrolled.
    var subtitle: String {
        var parts = [verificationLabel, enrolledAt.formatted(date: .abbreviated, time: .omitted)]
        if isLocked {
            parts.append("locked")
        }
        return parts.joined(separator: " · ")
    }

    private var verificationLabel: String {
        switch userVerification {
        case .pin: "PIN"
        case .platform: "Biometrics"
        case .none: "Second factor"
        @unknown default: "Device key"
        }
    }
}
