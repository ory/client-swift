/// Options for ``OryLoginFlow/createLoginFlow(options:)``.
///
/// Every property has a default, so `OryLoginFlowOptions()` starts a regular login flow — the
/// same flow ``OryLoginFlow/createLoginFlow()`` starts.
///
/// Two options start a flow for the user who is already signed in, instead of a new sign-in:
///
/// - ``refresh``: re-authentication. The user proves a credential again, for example before a
///   privileged change that failed with ``OryClientError/reauthenticationRequired``.
/// - ``aal`` set to ``OryAuthenticatorAssuranceLevel/aal2``: second-factor login, for a session
///   that failed with ``OryClientError/secondFactorRequired``.
///
/// ```swift
/// do {
///     let session = try await client.currentSession()
/// } catch OryClientError.secondFactorRequired {
///     let flow = try await client.createLoginFlow(options: OryLoginFlowOptions(aal: .aal2))
///     // Render the second-factor fields, then submitLoginFlow(_:values:pressing:).
/// }
/// ```
///
/// Both use the stored session token, so ``OryLoginFlow/createLoginFlow(options:)`` throws
/// ``OryClientError/notAuthenticated`` when no session is stored.
public struct OryLoginFlowOptions: Sendable, Equatable {

    /// Asks the signed-in user to authenticate again, even though their session is valid.
    ///
    /// Use it when a privileged change, such as a settings update, failed with
    /// ``OryClientError/reauthenticationRequired`` because the session was established too long
    /// ago. A successful submit refreshes the existing session instead of creating a new one.
    /// Defaults to `false`.
    public var refresh: Bool

    /// The authenticator assurance level the flow must reach, or `nil` for the project's
    /// default (a first-factor sign-in).
    ///
    /// Set ``OryAuthenticatorAssuranceLevel/aal2`` to sign the current session in with a
    /// second factor. Ory accepts only
    /// ``OryAuthenticatorAssuranceLevel/aal1`` and ``OryAuthenticatorAssuranceLevel/aal2``;
    /// any other value is rejected by the server. When the session already has the requested
    /// level, the server rejects the flow with ``OryClientError/server(status:id:messages:)``
    /// and ``OryErrorID/sessionAlreadyAvailable``, so check
    /// ``OrySession/authenticatorAssuranceLevel`` first. Defaults to `nil`.
    public var aal: OryAuthenticatorAssuranceLevel?

    /// Creates login flow options.
    ///
    /// - Parameters:
    ///   - refresh: Whether to re-authenticate the signed-in user. Defaults to `false`.
    ///   - aal: The assurance level to reach, or `nil` for the project's default.
    public init(refresh: Bool = false, aal: OryAuthenticatorAssuranceLevel? = nil) {
        self.refresh = refresh
        self.aal = aal
    }

    var belongsToSession: Bool {
        refresh || (aal ?? .aal1) >= .aal2
    }
}

/// Options for ``OryRegistrationFlow/createRegistrationFlow(options:)``.
///
/// Every property has a default, so `OryRegistrationFlowOptions()` starts a regular
/// registration flow — the same flow ``OryRegistrationFlow/createRegistrationFlow()`` starts.
public struct OryRegistrationFlowOptions: Sendable, Equatable {

    /// Creates options with every property at its default.
    public init() {}
}

/// Options for ``OryVerificationFlow/createVerificationFlow(options:)``.
///
/// Every property has a default, so `OryVerificationFlowOptions()` starts a regular
/// verification flow — the same flow ``OryVerificationFlow/createVerificationFlow()`` starts.
public struct OryVerificationFlowOptions: Sendable, Equatable {

    /// Creates options with every property at its default.
    public init() {}
}

/// Options for ``OryRecoveryFlow/createRecoveryFlow(options:)``.
///
/// Every property has a default, so `OryRecoveryFlowOptions()` starts a regular recovery flow —
/// the same flow ``OryRecoveryFlow/createRecoveryFlow()`` starts.
public struct OryRecoveryFlowOptions: Sendable, Equatable {

    /// Creates options with every property at its default.
    public init() {}
}

/// Options for ``OrySettingsFlow/createSettingsFlow(options:)``.
///
/// Every property has a default, so `OrySettingsFlowOptions()` starts a regular settings flow —
/// the same flow ``OrySettingsFlow/createSettingsFlow()`` starts.
public struct OrySettingsFlowOptions: Sendable, Equatable {

    /// Creates options with every property at its default.
    public init() {}
}
