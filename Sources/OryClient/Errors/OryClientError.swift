import Foundation

/// A user-facing message returned by Ory, for example a validation error on a flow.
///
/// These are localized and safe to show to users. To show your own wording instead, match
/// on ``id`` and fill in the values from ``context``:
///
/// ```swift
/// // 4000003: "length must be >= %d, but got %d"
/// if message.id == 4_000_003, case let .int(minimum)? = message.context["min_length"] {
///     label.text = String(localized: "Use at least \(minimum) characters.")
/// }
/// ```
public struct OryUIMessage: Sendable, Hashable {

    /// The kind of message.
    ///
    /// A wrapper around the server's message type rather than an enum, so a type added by a
    /// newer backend still decodes. Compare against the constants, and keep a `default:` arm
    /// in a `switch`.
    public struct Kind: RawRepresentable, Sendable, Hashable, CustomStringConvertible {

        /// The message type as Ory sends it, for example `error`.
        public let rawValue: String

        /// Creates a kind from the message type Ory sends.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String { rawValue }

        /// Neutral information, such as a hint.
        public static let info = Kind(rawValue: "info")

        /// A problem the user must fix, such as a validation error.
        public static let error = Kind(rawValue: "error")

        /// Confirmation that an action succeeded.
        public static let success = Kind(rawValue: "success")

        /// A message Ory sent without a type. Show the text as neutral information.
        public static let unknown = Kind(rawValue: "unknown")
    }

    /// The Ory message ID, useful for matching specific messages programmatically.
    public let id: Int

    /// The human-readable, localized message text.
    public let text: String

    /// The kind of message.
    public let kind: Kind

    /// The values Ory substituted into ``text``, keyed by name — for example `min_length` and
    /// `actual_length` for a too-short value. Use them to build your own localized text.
    /// Empty when the message has no values.
    public let context: [String: OryJSONValue]

    /// Creates a UI message.
    public init(id: Int, text: String, kind: Kind, context: [String: OryJSONValue] = [:]) {
        self.id = id
        self.text = text
        self.kind = kind
        self.context = context
    }
}

/// An error thrown by ``OryClient``.
///
/// Match the cases you can act on and let the rest fall through to a generic handler — for
/// example, route to a sign-in screen on ``notAuthenticated`` or ``sessionExpired``, and show
/// the ``OryUIMessage`` text from ``server(status:id:messages:)`` to the user.
///
/// ```swift
/// do {
///     let session = try await client.currentSession()
/// } catch OryClientError.notAuthenticated, OryClientError.sessionExpired {
///     presentSignIn()
/// } catch OryClientError.server(_, _, let messages) {
///     show(messages.map(\.text))
/// } catch {
///     showGenericError()
/// }
/// ```
///
/// - Important: New cases are added in minor releases as Ory grows new conditions. End a
///   `switch` that lists every case with `@unknown default:`, so a new case raises a warning
///   instead of a build error, or use `default:` when you handle only some cases.
///   Conditions that only differ in *which* server rule was hit — rather than in what the app
///   should do — do not become cases: they arrive as ``server(status:id:messages:)`` with an
///   ``OryErrorID``, which is an open type precisely so an id this build has never seen still
///   decodes.
public enum OryClientError: Error, Sendable {

    /// No session is stored, so the request was not attempted. The user needs to sign in.
    case notAuthenticated

    /// The server rejected the session as expired or invalid (HTTP 401/403).
    case sessionExpired

    /// The session is valid but was established too long ago for a privileged change such as
    /// setting a new PIN or removing a device (`session_refresh_required`).
    ///
    /// The user is still signed in — do **not** send them to a full sign-in. Ask them to prove
    /// their credential again and retry: start a re-authentication flow with
    /// `createLoginFlow(options: OryLoginFlowOptions(refresh: true))`, or step up with
    /// ``OryDeviceStepUp/authenticateWithDevice(pin:)`` when the device is enrolled. Ory
    /// Network's privileged window is 15 minutes by default.
    case reauthenticationRequired

    /// The project requires a second factor that this identity has not enrolled yet
    /// (`session_aal2_enrollment_required`).
    ///
    /// Distinct from ``secondFactorRequired``: there is no factor to prompt for, so send the
    /// user through enrollment — for example ``OryDeviceEnrollment/enrollDevice(name:protection:)``.
    case secondFactorEnrollmentRequired

    /// The flow expired before it was submitted (HTTP 410).
    ///
    /// Flows are short-lived, so this is routine whenever a user is interrupted mid-sign-in.
    /// Continue with the replacement flow, or start a fresh one; the user's input is not
    /// recoverable.
    ///
    /// - Parameter replacementFlowID: The flow the server already created to replace the
    ///   expired one, when it named one. It carries the "this took too long" message, so fetch
    ///   it with the flow's `get…Flow(id:)` method — for example
    ///   ``OryLoginFlow/getLoginFlow(id:)`` — instead of starting from scratch.
    case flowExpired(replacementFlowID: String?)

    /// The flow cannot continue in the app: the server asks to continue in a browser at
    /// `redirectURL` (HTTP 422, `browser_location_change_required`).
    ///
    /// It happens when the user picks a method that signs in at a third party, such as a
    /// social sign-in provider (``OryNodeGroup/oidc``) or enterprise SSO (``OryNodeGroup/saml``).
    /// Remove those methods from the screen when your app does not handle this error.
    ///
    /// - Parameter redirectURL: The page the server wants the browser to open.
    case browserLocationChangeRequired(redirectURL: URL)

    /// The request was rate limited (HTTP 429). Back off before retrying.
    ///
    /// - Parameter retryAfter: How long the server asked the client to wait, in seconds, when
    ///   it said. Honour it — retrying sooner extends the limit.
    case rateLimited(retryAfter: TimeInterval?)

    /// The first factor succeeded, but the project requires a second factor (AAL2) that
    /// the session does not yet satisfy.
    ///
    /// The session token is valid and stored — do **not** send the user back to full
    /// sign-in. Instead prompt the second factor: start a second-factor login flow with
    /// `createLoginFlow(options: OryLoginFlowOptions(aal: .aal2))` and submit it, or, when
    /// this device is enrolled, call ``OryClientProtocol/authenticateWithDevice(pin:)``,
    /// passing the PIN when ``OryClientProtocol/deviceEnrollment()`` reports a PIN key.
    ///
    /// ```swift
    /// do {
    ///     let session = try await client.currentSession()
    /// } catch OryClientError.secondFactorRequired {
    ///     switch try await client.deviceEnrollment() {
    ///     case .enrolled(.pin):
    ///         _ = try await client.authenticateWithDevice(pin: enteredPIN)  // AAL2
    ///     case .enrolled:
    ///         _ = try await client.authenticateWithDevice()                 // AAL2
    ///     default:
    ///         let flow = try await client.createLoginFlow(options: OryLoginFlowOptions(aal: .aal2))
    ///         // Render the flow and submit it with submitLoginFlow(_:values:pressing:).
    ///     }
    /// }
    /// ```
    case secondFactorRequired

    /// A transport-level failure, such as no connectivity or a timeout.
    case network(underlying: any Error & Sendable)

    /// The server returned an error this client does not model as its own case.
    ///
    /// - Parameters:
    ///   - status: The HTTP status.
    ///   - id: Ory's machine-readable ``OryErrorID``, when the body carried one. This is the
    ///     stable way to tell conditions apart — match against it for anything the cases above
    ///     do not cover, for example `id == .identityDisabled`.
    ///   - messages: User-facing text, safe to show. On a rejected form submission these are
    ///     the validation messages.
    case server(status: Int, id: OryErrorID?, messages: [OryUIMessage])

    /// The response could not be decoded into the expected shape.
    case unexpectedResponse(underlying: any Error & Sendable)

    /// Reading or writing ``OrySessionStorage`` failed.
    case storage(underlying: any Error & Sendable)

    /// This device cannot perform the requested device authentication.
    ///
    /// The Secure Enclave and App Attest are unavailable — typically because the code is
    /// running on the Simulator, on an unsupported device, or without the App Attest
    /// capability. Check
    /// ``OryClientProtocol/isDeviceAuthenticationAvailable`` and
    /// ``OryClientProtocol/availableDeviceAuthenticationMethods`` before offering device
    /// authentication so you never reach this case at runtime.
    case deviceAuthenticationUnavailable

    /// Another device operation using the same key store is still running in this process.
    ///
    /// This operation was rejected before reading the key, showing biometrics or sending
    /// a request. Wait for the active operation to finish before offering a retry. This
    /// is not an invalid PIN attempt and does not change the stored session or key.
    case deviceAuthenticationOperationInProgress

    /// The Ory project does not offer device authentication.
    ///
    /// The settings flow did not include a device authentication challenge, so the
    /// method is not enabled for your project. Enable the `deviceauthn` method in the
    /// Ory Console.
    case deviceAuthenticationNotEnabled

    /// No usable device key is enrolled on this device.
    ///
    /// Call ``OryClientProtocol/enrollDevice(name:protection:)`` first. Passwordless sign-in
    /// also throws this for a key enrolled with ``OryDeviceProtection/none``, which is a
    /// second factor only. This also happens after the
    /// app is reinstalled, because the Secure Enclave key is destroyed on uninstall — in
    /// that case enroll again. On the PIN paths it additionally means the stored PIN
    /// material is unusable (its sealing key or blob is gone); enroll the PIN again.
    case deviceAuthenticationNotEnrolled

    /// This device holds a key for a different account than the one signed in.
    ///
    /// A device holds a key for one account at a time. Enrolling would replace the other
    /// account's key and silently end its device sign-in, so ``OryClient`` refuses. Ask the user
    /// whether to move device sign-in to this account; if so, call
    /// ``OryClientProtocol/forgetDevice()`` and enroll again. Check ahead of time with
    /// ``OryClientProtocol/deviceEnrollment(for:)``.
    case deviceAuthenticationEnrolledForAnotherAccount

    /// A Secure Enclave or App Attest operation failed at runtime, for example while
    /// generating or attesting a key. `underlying` carries the platform error.
    case deviceAuthenticationFailed(underlying: any Error & Sendable)

    /// Biometric verification (Face ID / Touch ID / Optic ID) cannot be used on this device —
    /// no biometric hardware, none enrolled, or biometrics are locked out.
    ///
    /// Check ``OryClientProtocol/availableDeviceAuthenticationMethods`` (or
    /// ``OryClientProtocol/biometryType``) before offering biometric enrollment or sign-in so
    /// you never reach this case at runtime. When it does occur, fall back to PIN sign-in.
    case deviceAuthenticationBiometricsUnavailable

    /// The biometrics on this device changed since biometric sign-in was set up — a face or
    /// fingerprint was added or removed, Face ID was reset, or the passcode was removed — so
    /// the biometric device key can no longer be used.
    ///
    /// This protects the user when someone who knows the device passcode enrolls their own
    /// face or finger: the old enrollment stops working instead of accepting the new biometric.
    /// It does not recover. Sign the user in another way (for example with their password),
    /// then call ``OryClientProtocol/forgetDevice()`` and offer
    /// ``OryClientProtocol/enrollDevice(name:protection:)`` with
    /// ``OryDeviceProtection/biometrics`` again. The old credential stays
    /// listed in ``OryClientProtocol/enrolledDevices()`` until it is removed.
    case deviceAuthenticationBiometricsChanged

    /// The user cancelled the biometric (Face ID / Touch ID / Optic ID) prompt, or chose the
    /// fallback. Not an error to report loudly — the user simply declined; let them retry or
    /// offer PIN sign-in instead.
    case deviceAuthenticationCancelled

    /// The server rejected the PIN proof: the PIN entered does not match the one set when
    /// the device was enrolled.
    ///
    /// The PIN is never validated on the device — the Kratos server is the only PIN
    /// oracle. Every wrong attempt counts toward the key's `pin_max_attempts`; at the
    /// limit the server locks the key, after which this same error is returned even for
    /// the correct PIN. Recover a locked or forgotten PIN with
    /// ``OryClientProtocol/resetDevicePIN(newPin:)``.
    case deviceAuthenticationInvalidPIN

    /// The enrolled key is PIN-protected and the call needs its PIN, but none was provided.
    /// The device signature alone cannot sign in or step up with a PIN key.
    ///
    /// Prompt the user for their PIN and pass it to
    /// ``OryClientProtocol/loginWithDevice(pin:)`` or
    /// ``OryClientProtocol/authenticateWithDevice(pin:)``.
    case deviceAuthenticationPINRequired
}

/// A `Sendable` wrapper for an arbitrary underlying error.
///
/// ``OrySessionStorage`` is a public protocol, so a custom implementation may throw an
/// error that is not `Sendable`. Wrapping it preserves a readable description while
/// keeping ``OryClientError`` `Sendable`.
struct UnderlyingError: Error, Sendable, LocalizedError {
    let message: String

    init(_ error: any Error) {
        self.message = String(describing: error)
    }

    var errorDescription: String? { message }
}

extension OryClientError: LocalizedError {

    // TODO: - Use localized strings
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not signed in."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .secondFactorRequired:
            return "Please verify with your second factor to continue."
        case .reauthenticationRequired:
            return "Please confirm it's you to continue."
        case .secondFactorEnrollmentRequired:
            return "Please set up a second factor to continue."
        case .flowExpired:
            return "This took too long. Please start again."
        case .browserLocationChangeRequired:
            return "This sign-in method needs to continue in a browser."
        case .rateLimited:
            return "Too many attempts. Please wait a moment and try again."
        case let .network(underlying):
            return "A network error occurred: \(underlying.localizedDescription)"
        case let .server(status, _, messages):
            if let text = messages.first?.text {
                return text
            }
            return "The server returned an error (status \(status))."
        case let .unexpectedResponse(underlying):
            return "The server response could not be read: \(underlying.localizedDescription)"
        case let .storage(underlying):
            return "Secure storage could not be accessed: \(underlying.localizedDescription)"
        case .deviceAuthenticationUnavailable:
            return "Device authentication is not available on this device."
        case .deviceAuthenticationOperationInProgress:
            return "Another device operation is in progress. Please wait for it to finish and try again."
        case .deviceAuthenticationNotEnabled:
            return "Device authentication is not enabled for this Ory project."
        case .deviceAuthenticationNotEnrolled:
            return "No device is enrolled for device authentication on this device."
        case .deviceAuthenticationEnrolledForAnotherAccount:
            return "This device is set up for another account."
        case let .deviceAuthenticationFailed(underlying):
            return "Device authentication failed: \(underlying.localizedDescription)"
        case .deviceAuthenticationBiometricsUnavailable:
            return "Face ID or Touch ID is not available on this device."
        case .deviceAuthenticationBiometricsChanged:
            return "Face ID or Touch ID changed on this device. Sign in another way, then set up biometric sign-in again."
        case .deviceAuthenticationCancelled:
            return "Verification was cancelled."
        case .deviceAuthenticationInvalidPIN:
            return "That PIN is incorrect. Please try again."
        case .deviceAuthenticationPINRequired:
            return "Enter your PIN to verify this device."
        }
    }
}
