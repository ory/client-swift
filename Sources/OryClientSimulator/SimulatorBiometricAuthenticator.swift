#if targetEnvironment(simulator)
import Foundation
import OryClient

/// A ``OryBiometricAuthenticator`` for Simulator test runs: reports the configured biometry
/// as present and resolves every prompt with a predetermined outcome instead of showing
/// the system Face ID / Touch ID prompt — which cannot be satisfied in headless test
/// environments such as CI.
///
/// Inject it next to ``RelaxedDeviceKeyAuthenticator`` to exercise biometric enrollment,
/// sign-in, and step-up end to end on the Simulator:
///
/// ```swift
/// let biometrics = SimulatorBiometricAuthenticator()
/// let config = OryClientConfiguration(
///     projectURL: url,
///     deviceKeyAuthenticator: RelaxedDeviceKeyAuthenticator(),
///     biometricAuthenticator: biometrics
/// )
/// // ...
/// #expect(await biometrics.recorder.promptCount == 1)
/// ```
///
/// Like the rest of `OryClientSimulator`, this type compiles to nothing in device
/// builds, so it can never replace the real biometric gate in a shipped app.
public struct SimulatorBiometricAuthenticator: OryBiometricAuthenticator {

    /// How a prompt resolves.
    public enum PromptOutcome: Sendable {

        /// The prompt succeeds, as if the user matched Face ID / Touch ID.
        case success

        /// The prompt is declined, throwing
        /// ``OryClientError/deviceAuthenticationCancelled`` — as if the user cancelled.
        case cancelled
    }

    /// Records the prompts a ``SimulatorBiometricAuthenticator`` resolved, so tests can
    /// assert whether — and how often — the biometric gate was evaluated.
    public actor Recorder {

        /// How many prompts were evaluated.
        public private(set) var promptCount = 0

        /// Creates an empty recorder.
        public init() {}

        func record() {
            promptCount += 1
        }
    }

    /// The biometry this simulated device reports. ``OryBiometryType/none`` makes the
    /// authenticator unavailable, so enrollment and sign-in fail the same way they would
    /// on a device without usable biometrics.
    public let biometryType: OryBiometryType

    /// Observes every evaluated prompt. Share one recorder between the authenticator and
    /// your assertions.
    public let recorder: Recorder

    private let outcome: PromptOutcome

    public var isAvailable: Bool { biometryType != .none }

    /// Creates a simulated biometric authenticator.
    ///
    /// - Parameters:
    ///   - biometryType: The biometry to report. Defaults to ``OryBiometryType/faceID``.
    ///   - outcome: How prompts resolve. Defaults to ``PromptOutcome/success``.
    ///   - recorder: The recorder that observes prompts. Defaults to a fresh one.
    public init(
        biometryType: OryBiometryType = .faceID,
        outcome: PromptOutcome = .success,
        recorder: Recorder = Recorder()
    ) {
        self.biometryType = biometryType
        self.outcome = outcome
        self.recorder = recorder
    }

    public func enroll(keyID _: String, reason _: String) async throws {
        try await prompt()
    }

    public func evaluate(keyID _: String, reason _: String) async throws {
        try await prompt()
    }

    public func removeEnrollment(keyID _: String) async {}

    private func prompt() async throws {
        await recorder.record()
        guard isAvailable else {
            throw OryClientError.deviceAuthenticationBiometricsUnavailable
        }
        switch outcome {
        case .success:
            return
        case .cancelled:
            throw OryClientError.deviceAuthenticationCancelled
        }
    }
}
#endif
