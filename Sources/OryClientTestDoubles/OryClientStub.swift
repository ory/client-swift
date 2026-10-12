import Foundation
import OryClient

/// A configurable ``OryClientProtocol`` test double that also records calls.
///
/// Use it to drive code that depends on ``OryClientProtocol`` without a live backend.
/// Set a result per method, then assert how your code reacts and how often it called
/// through. Implemented as an `actor`, so it is thread-safe at compile time with no
/// locks.
///
/// ```swift
/// let stub = OryClientStub(currentSessionResult: .failure(.sessionExpired))
///
/// let viewModel = ProfileViewModel(ory: stub)
/// await viewModel.load()
///
/// #expect(await stub.currentSessionCallCount == 1)
/// ```
public actor OryClientStub: OryClientProtocol {

    private let deviceAuthenticationAvailable: Bool
    private let deviceAuthnMethods: Set<OryDeviceAuthenticationMethod>
    private let biometry: OryBiometryType
    private var currentSessionResult: Result<OrySession, OryClientError>
    private var logoutResult: Result<Void, OryClientError>
    private var createLoginFlowResult: Result<OryFlow, OryClientError>
    private var submitLoginFlowResult: Result<OryFlowResult<OryAuthenticatedSession>, OryClientError>
    private var createRegistrationFlowResult: Result<OryFlow, OryClientError>
    private var submitRegistrationFlowResult: Result<OryFlowResult<OryRegistrationResult>, OryClientError>
    private var createVerificationFlowResult: Result<OryFlow, OryClientError>
    private var getVerificationFlowResult: Result<OryFlow, OryClientError>
    private var submitVerificationFlowResult: Result<OryFlowResult<OryVerificationResult>, OryClientError>
    private var createRecoveryFlowResult: Result<OryFlow, OryClientError>
    private var submitRecoveryFlowResult: Result<OryFlowResult<OryRecoveryResult>, OryClientError>
    private var createSettingsFlowResult: Result<OryFlow, OryClientError>
    private var getSettingsFlowResult: Result<OryFlow, OryClientError>
    private var submitSettingsFlowResult: Result<OryFlowResult<OrySettingsResult>, OryClientError>
    private var deviceEnrollmentResult: Result<OryDeviceEnrollmentState, OryClientError>
    private var enrollDeviceResult: Result<Void, OryClientError>
    private var authenticateWithDeviceResult: Result<OryAuthenticatedSession, OryClientError>
    private var loginWithDeviceResult: Result<OryAuthenticatedSession, OryClientError>
    private var removeDeviceResult: Result<Void, OryClientError>
    private var enrolledDevicesResult: Result<[OryEnrolledDevice], OryClientError>
    private var resetDevicePINResult: Result<Void, OryClientError>
    private var forgetDeviceResult: Result<Void, OryClientError>

    private var currentSessionCalls = 0
    private var logoutCalls = 0
    private var createLoginFlowCalls = 0
    private var submitLoginFlowCalls = 0
    private var createRegistrationFlowCalls = 0
    private var submitRegistrationFlowCalls = 0
    private var createVerificationFlowCalls = 0
    private var getVerificationFlowCalls = 0
    private var submitVerificationFlowCalls = 0
    private var createRecoveryFlowCalls = 0
    private var submitRecoveryFlowCalls = 0
    private var createSettingsFlowCalls = 0
    private var getSettingsFlowCalls = 0
    private var submitSettingsFlowCalls = 0
    private var deviceEnrollmentCalls = 0
    private var enrollDeviceCalls = 0
    private var authenticateWithDeviceCalls = 0
    private var loginWithDeviceCalls = 0
    private var removeDeviceCalls = 0
    private var enrolledDevicesCalls = 0
    private var removedDevices: [OryEnrolledDevice] = []
    private var resetDevicePINCalls = 0
    private var forgetDeviceCalls = 0
    private var lastPIN: String?
    private var lastSubmittedValues: OryFormValues?
    private var lastPressedAction: OryInputField?
    private var lastEnrolledDeviceName: String?
    private var lastEnrolledDeviceProtection: OryDeviceProtection?
    private var lastRequestedSettingsFlowID: String?

    /// Creates a stub. Each result defaults to throwing ``OryClientError/notAuthenticated``.
    public init(
        deviceAuthenticationAvailable: Bool = true,
        availableDeviceAuthenticationMethods: Set<OryDeviceAuthenticationMethod> = [.pin, .biometric],
        biometryType: OryBiometryType = .faceID,
        currentSessionResult: Result<OrySession, OryClientError> = .failure(.notAuthenticated),
        logoutResult: Result<Void, OryClientError> = .success(()),
        createLoginFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitLoginFlowResult: Result<OryFlowResult<OryAuthenticatedSession>, OryClientError> = .failure(.notAuthenticated),
        createRegistrationFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitRegistrationFlowResult: Result<OryFlowResult<OryRegistrationResult>, OryClientError> = .failure(.notAuthenticated),
        createVerificationFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getVerificationFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitVerificationFlowResult: Result<OryFlowResult<OryVerificationResult>, OryClientError> = .failure(.notAuthenticated),
        createRecoveryFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitRecoveryFlowResult: Result<OryFlowResult<OryRecoveryResult>, OryClientError> = .failure(.notAuthenticated),
        createSettingsFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        getSettingsFlowResult: Result<OryFlow, OryClientError> = .failure(.notAuthenticated),
        submitSettingsFlowResult: Result<OryFlowResult<OrySettingsResult>, OryClientError> = .failure(.notAuthenticated),
        deviceEnrollmentResult: Result<OryDeviceEnrollmentState, OryClientError> = .success(.notEnrolled),
        enrollDeviceResult: Result<Void, OryClientError> = .success(()),
        authenticateWithDeviceResult: Result<OryAuthenticatedSession, OryClientError> = .failure(.notAuthenticated),
        loginWithDeviceResult: Result<OryAuthenticatedSession, OryClientError> = .failure(.notAuthenticated),
        removeDeviceResult: Result<Void, OryClientError> = .success(()),
        enrolledDevicesResult: Result<[OryEnrolledDevice], OryClientError> = .success([]),
        resetDevicePINResult: Result<Void, OryClientError> = .success(()),
        forgetDeviceResult: Result<Void, OryClientError> = .success(())
    ) {
        self.deviceAuthenticationAvailable = deviceAuthenticationAvailable
        self.deviceAuthnMethods = availableDeviceAuthenticationMethods
        self.biometry = biometryType
        self.currentSessionResult = currentSessionResult
        self.logoutResult = logoutResult
        self.createLoginFlowResult = createLoginFlowResult
        self.submitLoginFlowResult = submitLoginFlowResult
        self.createRegistrationFlowResult = createRegistrationFlowResult
        self.submitRegistrationFlowResult = submitRegistrationFlowResult
        self.createVerificationFlowResult = createVerificationFlowResult
        self.getVerificationFlowResult = getVerificationFlowResult
        self.submitVerificationFlowResult = submitVerificationFlowResult
        self.createRecoveryFlowResult = createRecoveryFlowResult
        self.submitRecoveryFlowResult = submitRecoveryFlowResult
        self.createSettingsFlowResult = createSettingsFlowResult
        self.getSettingsFlowResult = getSettingsFlowResult
        self.submitSettingsFlowResult = submitSettingsFlowResult
        self.deviceEnrollmentResult = deviceEnrollmentResult
        self.enrollDeviceResult = enrollDeviceResult
        self.authenticateWithDeviceResult = authenticateWithDeviceResult
        self.loginWithDeviceResult = loginWithDeviceResult
        self.removeDeviceResult = removeDeviceResult
        self.enrolledDevicesResult = enrolledDevicesResult
        self.resetDevicePINResult = resetDevicePINResult
        self.forgetDeviceResult = forgetDeviceResult
    }

    // MARK: - Configuration

    /// Sets the result the next call to ``currentSession()`` returns.
    public func setCurrentSessionResult(_ result: Result<OrySession, OryClientError>) {
        currentSessionResult = result
    }

    /// Sets the result the next call to ``logout()`` returns.
    public func setLogoutResult(_ result: Result<Void, OryClientError>) {
        logoutResult = result
    }

    /// Sets the result the next call to ``createLoginFlow()`` returns.
    public func setCreateLoginFlowResult(_ result: Result<OryFlow, OryClientError>) {
        createLoginFlowResult = result
    }

    /// Sets the result the next call to ``submitLoginFlow(_:values:pressing:)`` returns.
    public func setSubmitLoginFlowResult(_ result: Result<OryFlowResult<OryAuthenticatedSession>, OryClientError>) {
        submitLoginFlowResult = result
    }

    /// Sets the result the next call to ``createRegistrationFlow()`` returns.
    public func setCreateRegistrationFlowResult(_ result: Result<OryFlow, OryClientError>) {
        createRegistrationFlowResult = result
    }

    /// Sets the result the next call to ``submitRegistrationFlow(_:values:pressing:)`` returns.
    public func setSubmitRegistrationFlowResult(_ result: Result<OryFlowResult<OryRegistrationResult>, OryClientError>) {
        submitRegistrationFlowResult = result
    }

    /// Sets the result the next call to ``createVerificationFlow()`` returns.
    public func setCreateVerificationFlowResult(_ result: Result<OryFlow, OryClientError>) {
        createVerificationFlowResult = result
    }

    /// Sets the result the next call to ``getVerificationFlow(id:)`` returns.
    public func setGetVerificationFlowResult(_ result: Result<OryFlow, OryClientError>) {
        getVerificationFlowResult = result
    }

    /// Sets the result the next call to ``submitVerificationFlow(_:values:pressing:)`` returns.
    public func setSubmitVerificationFlowResult(_ result: Result<OryFlowResult<OryVerificationResult>, OryClientError>) {
        submitVerificationFlowResult = result
    }

    /// Sets the result the next call to ``createRecoveryFlow()`` returns.
    public func setCreateRecoveryFlowResult(_ result: Result<OryFlow, OryClientError>) {
        createRecoveryFlowResult = result
    }

    /// Sets the result the next call to ``submitRecoveryFlow(_:values:pressing:)`` returns.
    public func setSubmitRecoveryFlowResult(_ result: Result<OryFlowResult<OryRecoveryResult>, OryClientError>) {
        submitRecoveryFlowResult = result
    }

    /// Sets the result the next call to ``createSettingsFlow()`` returns.
    public func setCreateSettingsFlowResult(_ result: Result<OryFlow, OryClientError>) {
        createSettingsFlowResult = result
    }

    /// Sets the result the next call to ``getSettingsFlow(id:)`` returns.
    public func setGetSettingsFlowResult(_ result: Result<OryFlow, OryClientError>) {
        getSettingsFlowResult = result
    }

    /// Sets the result the next call to ``submitSettingsFlow(_:values:pressing:)`` returns.
    public func setSubmitSettingsFlowResult(_ result: Result<OryFlowResult<OrySettingsResult>, OryClientError>) {
        submitSettingsFlowResult = result
    }

    /// Sets the result the next call to ``deviceEnrollment()`` returns.
    public func setDeviceEnrollmentResult(_ result: Result<OryDeviceEnrollmentState, OryClientError>) {
        deviceEnrollmentResult = result
    }

    /// Sets the result the next call to ``enrollDevice(name:protection:)`` returns.
    public func setEnrollDeviceResult(_ result: Result<Void, OryClientError>) {
        enrollDeviceResult = result
    }

    /// Sets the result the next call to ``authenticateWithDevice(pin:)`` returns.
    public func setAuthenticateWithDeviceResult(_ result: Result<OryAuthenticatedSession, OryClientError>) {
        authenticateWithDeviceResult = result
    }

    /// Sets the result the next call to ``loginWithDevice(pin:)`` returns.
    public func setLoginWithDeviceResult(_ result: Result<OryAuthenticatedSession, OryClientError>) {
        loginWithDeviceResult = result
    }

    /// Sets the result calls to ``enrolledDevices()`` return.
    public func setEnrolledDevicesResult(_ result: Result<[OryEnrolledDevice], OryClientError>) {
        enrolledDevicesResult = result
    }

    /// Sets the result the next call to ``removeDevice()`` returns.
    public func setRemoveDeviceResult(_ result: Result<Void, OryClientError>) {
        removeDeviceResult = result
    }

    /// Sets the result the next call to ``resetDevicePIN(newPin:)`` returns.
    public func setResetDevicePINResult(_ result: Result<Void, OryClientError>) {
        resetDevicePINResult = result
    }

    /// Sets the result the next call to ``forgetDevice()`` returns.
    public func setForgetDeviceResult(_ result: Result<Void, OryClientError>) {
        forgetDeviceResult = result
    }

    // MARK: - Recorded calls

    /// How many times ``currentSession()`` has been called.
    public var currentSessionCallCount: Int { currentSessionCalls }

    /// How many times ``logout()`` has been called.
    public var logoutCallCount: Int { logoutCalls }

    /// How many times ``createLoginFlow()`` has been called.
    public var createLoginFlowCallCount: Int { createLoginFlowCalls }

    /// How many times ``submitLoginFlow(_:values:pressing:)`` has been called.
    public var submitLoginFlowCallCount: Int { submitLoginFlowCalls }

    /// How many times ``createRegistrationFlow()`` has been called.
    public var createRegistrationFlowCallCount: Int { createRegistrationFlowCalls }

    /// How many times ``submitRegistrationFlow(_:values:pressing:)`` has been called.
    public var submitRegistrationFlowCallCount: Int { submitRegistrationFlowCalls }

    /// How many times ``createVerificationFlow()`` has been called.
    public var createVerificationFlowCallCount: Int { createVerificationFlowCalls }

    /// How many times ``getVerificationFlow(id:)`` has been called.
    public var getVerificationFlowCallCount: Int { getVerificationFlowCalls }

    /// How many times ``submitVerificationFlow(_:values:pressing:)`` has been called.
    public var submitVerificationFlowCallCount: Int { submitVerificationFlowCalls }

    /// How many times ``createRecoveryFlow()`` has been called.
    public var createRecoveryFlowCallCount: Int { createRecoveryFlowCalls }

    /// How many times ``submitRecoveryFlow(_:values:pressing:)`` has been called.
    public var submitRecoveryFlowCallCount: Int { submitRecoveryFlowCalls }

    /// How many times ``createSettingsFlow()`` has been called.
    public var createSettingsFlowCallCount: Int { createSettingsFlowCalls }

    /// How many times ``getSettingsFlow(id:)`` has been called.
    public var getSettingsFlowCallCount: Int { getSettingsFlowCalls }

    /// The id most recently passed to ``getSettingsFlow(id:)``.
    public var requestedSettingsFlowID: String? { lastRequestedSettingsFlowID }

    /// How many times ``submitSettingsFlow(_:values:pressing:)`` has been called.
    public var submitSettingsFlowCallCount: Int { submitSettingsFlowCalls }

    /// How many times ``deviceEnrollment()`` has been called.
    public var deviceEnrollmentCallCount: Int { deviceEnrollmentCalls }

    /// How many times ``enrollDevice(name:protection:)`` has been called.
    public var enrollDeviceCallCount: Int { enrollDeviceCalls }

    /// How many times ``authenticateWithDevice(pin:)`` has been called.
    public var authenticateWithDeviceCallCount: Int { authenticateWithDeviceCalls }

    /// How many times ``loginWithDevice(pin:)`` has been called.
    public var loginWithDeviceCallCount: Int { loginWithDeviceCalls }

    /// How many times ``enrolledDevices()`` has been called.
    public var enrolledDevicesCallCount: Int { enrolledDevicesCalls }

    /// The devices passed to ``removeDevice(_:)``, in call order.
    public var removedDeviceArguments: [OryEnrolledDevice] { removedDevices }

    /// How many times ``removeDevice()`` has been called.
    public var removeDeviceCallCount: Int { removeDeviceCalls }

    /// How many times ``resetDevicePIN(newPin:)`` has been called.
    public var resetDevicePINCallCount: Int { resetDevicePINCalls }

    /// How many times ``forgetDevice()`` has been called.
    public var forgetDeviceCallCount: Int { forgetDeviceCalls }

    /// The PIN passed to the most recent enrollment, sign-in, step-up, or PIN reset; `nil` when
    /// that call carried no PIN.
    public var submittedPIN: String? { lastPIN }

    /// The values passed to the most recent submit (login, registration, or verification).
    public var submittedValues: OryFormValues? { lastSubmittedValues }

    /// The action pressed in the most recent submit (login or registration).
    public var pressedAction: OryInputField? { lastPressedAction }

    /// The device name passed to the most recent ``enrollDevice(name:protection:)`` call.
    public var enrolledDeviceName: String? { lastEnrolledDeviceName }

    /// The protection passed to the most recent ``enrollDevice(name:protection:)`` call.
    public var enrolledDeviceProtection: OryDeviceProtection? { lastEnrolledDeviceProtection }

    // MARK: - OryClientProtocol

    public nonisolated var isDeviceAuthenticationAvailable: Bool {
        deviceAuthenticationAvailable
    }

    public nonisolated var availableDeviceAuthenticationMethods: Set<OryDeviceAuthenticationMethod> {
        deviceAuthnMethods
    }

    public nonisolated var biometryType: OryBiometryType {
        biometry
    }

    public func currentSession() async throws -> OrySession {
        currentSessionCalls += 1
        return try currentSessionResult.get()
    }

    public func logout() async throws {
        logoutCalls += 1
        try logoutResult.get()
    }

    public func createLoginFlow() async throws -> OryFlow {
        createLoginFlowCalls += 1
        return try createLoginFlowResult.get()
    }

    public func submitLoginFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryAuthenticatedSession> {
        submitLoginFlowCalls += 1
        lastSubmittedValues = values
        lastPressedAction = action
        return try submitLoginFlowResult.get()
    }

    public func createRegistrationFlow() async throws -> OryFlow {
        createRegistrationFlowCalls += 1
        return try createRegistrationFlowResult.get()
    }

    public func submitRegistrationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRegistrationResult> {
        submitRegistrationFlowCalls += 1
        lastSubmittedValues = values
        lastPressedAction = action
        return try submitRegistrationFlowResult.get()
    }

    public func createVerificationFlow() async throws -> OryFlow {
        createVerificationFlowCalls += 1
        return try createVerificationFlowResult.get()
    }

    public func getVerificationFlow(id: String) async throws -> OryFlow {
        getVerificationFlowCalls += 1
        return try getVerificationFlowResult.get()
    }

    public func submitVerificationFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryVerificationResult> {
        submitVerificationFlowCalls += 1
        lastSubmittedValues = values
        lastPressedAction = action
        return try submitVerificationFlowResult.get()
    }

    public func createRecoveryFlow() async throws -> OryFlow {
        createRecoveryFlowCalls += 1
        return try createRecoveryFlowResult.get()
    }

    public func submitRecoveryFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OryRecoveryResult> {
        submitRecoveryFlowCalls += 1
        lastSubmittedValues = values
        lastPressedAction = action
        return try submitRecoveryFlowResult.get()
    }

    public func createSettingsFlow() async throws -> OryFlow {
        createSettingsFlowCalls += 1
        return try createSettingsFlowResult.get()
    }

    public func getSettingsFlow(id: String) async throws -> OryFlow {
        getSettingsFlowCalls += 1
        lastRequestedSettingsFlowID = id
        return try getSettingsFlowResult.get()
    }

    public func submitSettingsFlow(
        _ flow: OryFlow,
        values: OryFormValues,
        pressing action: OryInputField
    ) async throws -> OryFlowResult<OrySettingsResult> {
        submitSettingsFlowCalls += 1
        lastSubmittedValues = values
        lastPressedAction = action
        return try submitSettingsFlowResult.get()
    }

    public func deviceEnrollment() async throws -> OryDeviceEnrollmentState {
        deviceEnrollmentCalls += 1
        return try deviceEnrollmentResult.get()
    }

    public func enrollDevice(name: String, protection: OryDeviceProtection) async throws {
        enrollDeviceCalls += 1
        lastEnrolledDeviceName = name
        lastEnrolledDeviceProtection = protection
        if case let .pin(pin) = protection {
            lastPIN = pin
        } else {
            lastPIN = nil
        }
        try enrollDeviceResult.get()
    }

    public func authenticateWithDevice(pin: String?) async throws -> OryAuthenticatedSession {
        authenticateWithDeviceCalls += 1
        lastPIN = pin
        return try authenticateWithDeviceResult.get()
    }

    public func loginWithDevice(pin: String?) async throws -> OryAuthenticatedSession {
        loginWithDeviceCalls += 1
        lastPIN = pin
        return try loginWithDeviceResult.get()
    }

    public func enrolledDevices() async throws -> [OryEnrolledDevice] {
        enrolledDevicesCalls += 1
        return try enrolledDevicesResult.get()
    }

    public func removeDevice(_ device: OryEnrolledDevice) async throws {
        removeDeviceCalls += 1
        removedDevices.append(device)
        try removeDeviceResult.get()
    }

    public func removeDevice() async throws {
        removeDeviceCalls += 1
        try removeDeviceResult.get()
    }

    public func resetDevicePIN(newPin: String) async throws {
        resetDevicePINCalls += 1
        lastPIN = newPin
        try resetDevicePINResult.get()
    }

    public func forgetDevice() async throws {
        forgetDeviceCalls += 1
        try forgetDeviceResult.get()
    }
}
