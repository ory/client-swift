import Foundation

extension OryClient: OryDeviceCapabilities, OryDeviceEnrollment, OryDeviceStepUp, OryDeviceLogin, OryDeviceManagement {

    public var isDeviceAuthenticationAvailable: Bool {
        deviceAuthenticator.isAvailable
    }

    public var availableDeviceAuthenticationMethods: Set<OryDeviceAuthenticationMethod> {
        guard deviceAuthenticator.isAvailable else { return [] }
        var methods: Set<OryDeviceAuthenticationMethod> = [.pin]
        if biometricAuthenticator.isAvailable {
            methods.insert(.biometric)
        }
        return methods
    }

    public var biometryType: OryBiometryType {
        biometricAuthenticator.biometryType
    }

    public func deviceEnrollment() async throws -> OryDeviceEnrollmentState {
        let key: OryStoredDeviceKey?
        do {
            key = try await deviceKeyStore.enrolledKey()
        } catch {
            throw Self.storageError(error)
        }
        return key.map { .enrolled($0.userVerification) } ?? .notEnrolled
    }

    public func deviceEnrollment(for session: OrySession) async throws -> OryDeviceEnrollmentState {
        let key: OryStoredDeviceKey?
        do {
            key = try await deviceKeyStore.enrolledKey()
        } catch {
            throw Self.storageError(error)
        }
        guard let key else { return .notEnrolled }
        if let identityID = session.identity?.id, key.identityID != identityID {
            return .enrolledForAnotherAccount
        }
        return .enrolled(key.userVerification)
    }

    public func forgetDevice() async throws {
        try await withDeviceOperation {
            try await clearDeviceKey()
        }
    }

    public func enrollDevice(name: String, protection: OryDeviceProtection) async throws {
        switch protection {
        case .none:
            try await enrollPossessionKey(name: name)
        case let .pin(pin):
            try await enrollPINKey(name: name, pin: pin)
        case .biometrics:
            try await enrollBiometricKey(name: name)
        }
    }

    private func enrollPossessionKey(name: String) async throws {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }

            let token = try await requireSessionToken()
            let challenge = try await deviceAuthn.createDeviceEnrollmentChallenge(sessionToken: token)
            try await requireNoKeyForAnotherAccount(challenge.identityID)
            let attestation = try await deviceAuthenticator.attestNewKey(challenge: challenge.nonce)
            let clientKeyID = try Self.attestedClientKeyID(attestation)
            let keyIDsAfterEnrollment = try await deviceAuthn.submitDeviceEnrollment(
                url: challenge.submitURL,
                sessionToken: token,
                attestation: attestation.attestation,
                deviceName: name,
                userVerification: .none
            )

            guard keyIDsAfterEnrollment.contains(clientKeyID) else {
                throw OryClientError.unexpectedResponse(underlying: DeviceEnrollmentError.newKeyNotFound)
            }

            try await storeDeviceKey(
                OryStoredDeviceKey(
                    clientKeyID: clientKeyID,
                    localKeyID: attestation.keyID,
                    userVerification: .none,
                    identityID: challenge.identityID
                )
            )
        }
    }

    private func enrollBiometricKey(name: String) async throws {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }
            guard biometricAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationBiometricsUnavailable
            }

            let token = try await requireSessionToken()
            let challenge = try await deviceAuthn.createDeviceEnrollmentChallenge(sessionToken: token)
            try await requireNoKeyForAnotherAccount(challenge.identityID)
            // A biometric key attests the bare nonce, exactly like a plain key — there is no
            // transport key or sealed secret; the biometric gate lives entirely on the client.
            let attestation = try await deviceAuthenticator.attestNewKey(challenge: challenge.nonce)
            let clientKeyID = try Self.attestedClientKeyID(attestation)

            // The key is registered as `user_verification: platform`, which the iOS backend
            // trusts because App Attest cannot prove the gating, so the enrolling user's
            // biometrics are confirmed and bound before the server learns about the key.
            try await biometricAuthenticator.enroll(keyID: attestation.keyID, reason: biometricEnrollReason)
            do {
                let keyIDsAfterEnrollment = try await deviceAuthn.submitDeviceEnrollment(
                    url: challenge.submitURL,
                    sessionToken: token,
                    attestation: attestation.attestation,
                    deviceName: name,
                    userVerification: .platform
                )

                guard keyIDsAfterEnrollment.contains(clientKeyID) else {
                    throw OryClientError.unexpectedResponse(underlying: DeviceEnrollmentError.newKeyNotFound)
                }

                try await storeDeviceKey(
                    OryStoredDeviceKey(
                        clientKeyID: clientKeyID,
                        localKeyID: attestation.keyID,
                        userVerification: .platform,
                        identityID: challenge.identityID
                    )
                )
            } catch {
                await biometricAuthenticator.removeEnrollment(keyID: attestation.keyID)
                throw error
            }
        }
    }

    private func enrollPINKey(name: String, pin: String) async throws {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }

            let token = try await requireSessionToken()
            let transportKey = pinVault.makeTransportKey()
            let challenge = try await deviceAuthn.createDeviceEnrollmentChallenge(sessionToken: token)
            try await requireNoKeyForAnotherAccount(challenge.identityID)
            // A PIN-protected key attests over SHA256(nonce ‖ transport_public_key), not the bare
            // nonce, binding the HPKE transport key into the attestation the server verifies.
            let boundChallenge = pinVault.enrollmentChallenge(nonce: challenge.nonce, transportKey: transportKey)
            let attestation = try await deviceAuthenticator.attestNewKey(challenge: boundChallenge)
            let clientKeyID = try Self.attestedClientKeyID(attestation)
            let result = try await deviceAuthn.submitDevicePINEnrollment(
                url: challenge.submitURL,
                sessionToken: token,
                attestation: attestation.attestation,
                deviceName: name,
                transportPublicKey: transportKey.publicKey
            )

            guard result.keyIDs.contains(clientKeyID) else {
                throw OryClientError.unexpectedResponse(underlying: DeviceEnrollmentError.newKeyNotFound)
            }

            try await storeSealedPIN(
                result.sealed,
                transportKey: transportKey,
                clientKeyID: clientKeyID,
                localKeyID: attestation.keyID,
                identityID: challenge.identityID,
                pin: pin
            )
        }
    }

    public func loginWithDevice(pin: String?) async throws -> OryAuthenticatedSession {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }

            let key = try await requireEnrolledKey()
            if let protected = key.pinSecret {
                guard let pin else {
                    throw OryClientError.deviceAuthenticationPINRequired
                }
                return try await loginWithPINKey(key, protected: protected, pin: pin)
            }
            guard key.userVerification == .platform else {
                // A possession-only key is a second factor and cannot sign in on its own.
                throw OryClientError.deviceAuthenticationNotEnrolled
            }
            return try await loginWithBiometricKey(key)
        }
    }

    private func loginWithPINKey(
        _ key: OryStoredDeviceKey,
        protected: OryProtectedPINSecret,
        pin: String
    ) async throws -> OryAuthenticatedSession {
        // A wrong PIN is not detectable here: unlocking yields a well-formed but wrong
        // secret, and the resulting pin_proof is submitted so the server — the only PIN
        // oracle — rejects it and counts the attempt toward pin_max_attempts.
        var pinBytes = Array(pin.utf8)
        var pinSecret = try pinVault.unlock(protected, pin: &pinBytes)
        defer { DevicePINVault.zeroize(&pinSecret) }
        let challenge = try await deviceAuthn.createDeviceFirstFactorLoginChallenge()
        let signature = try await signChallenge(key: key, challenge: challenge.nonce, reason: biometricSignInReason)
        let proof = pinVault.proof(pinSecret: pinSecret, clientKeyID: key.clientKeyID, nonce: challenge.nonce)
        let outcome: DeviceLoginOutcome
        do {
            outcome = try await deviceAuthn.submitDeviceFirstFactorLogin(
                url: challenge.submitURL,
                clientKeyID: key.clientKeyID,
                signature: signature,
                pinProof: proof
            )
        } catch let error as OryClientError {
            throw Self.mapPINRejection(error)
        }

        if let token = outcome.token {
            try await storeToken(token)
        }
        return OryAuthenticatedSession(session: outcome.session)
    }

    private func loginWithBiometricKey(_ key: OryStoredDeviceKey) async throws -> OryAuthenticatedSession {
        guard biometricAuthenticator.isAvailable else {
            throw OryClientError.deviceAuthenticationBiometricsUnavailable
        }

        let challenge = try await deviceAuthn.createDeviceFirstFactorLoginChallenge()
        // Biometric gate fires inside `signChallenge` for a `.platform` key. No `pin_proof`:
        // the server forbids one on a signature-only key.
        let signature = try await signChallenge(key: key, challenge: challenge.nonce, reason: biometricSignInReason)
        let outcome = try await deviceAuthn.submitDeviceFirstFactorLogin(
            url: challenge.submitURL,
            clientKeyID: key.clientKeyID,
            signature: signature,
            pinProof: nil
        )

        if let token = outcome.token {
            try await storeToken(token)
        }
        return OryAuthenticatedSession(session: outcome.session)
    }

    public func resetDevicePIN(newPin: String) async throws {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }

            let token = try await requireSessionToken()
            let key = try await requireEnrolledKey()
            guard key.pinSecret != nil else {
                // Only a PIN-protected key has a secret to re-issue; a plain 2FA key does not.
                throw OryClientError.deviceAuthenticationNotEnrolled
            }

            // Rotation proves the device by signature alone — the old PIN is never involved — and
            // the assurance level it demands is the project's settings-flow policy, not something
            // this client can decide. So submit with the session at hand and let the server rule:
            // a locked key no longer counts as a second factor, which is what makes a plain
            // password session enough to recover a forgotten PIN, while a working key still
            // requires AAL2 and surfaces `secondFactorRequired`.
            let transportKey = pinVault.makeTransportKey()
            let challenge = try await deviceAuthn.createDeviceEnrollmentChallenge(sessionToken: token)
            if key.identityID != challenge.identityID {
                throw OryClientError.deviceAuthenticationEnrolledForAnotherAccount
            }
            // The possession signature covers nonce ‖ transport_public_key (raw concatenation, not
            // hashed — unlike enrollment), binding the fresh secret to this transport key.
            let signedChallenge = pinVault.rotationChallenge(nonce: challenge.nonce, transportKey: transportKey)
            // A PIN key is not biometric-gated, so `signChallenge` signs without a prompt; routing
            // through it keeps every device signature on one path.
            let signature = try await signChallenge(key: key, challenge: signedChallenge, reason: biometricSignInReason)
            let sealed = try await deviceAuthn.submitDevicePINRotation(
                url: challenge.submitURL,
                sessionToken: token,
                clientKeyID: key.clientKeyID,
                signature: signature,
                transportPublicKey: transportKey.publicKey
            )

            try await storeSealedPIN(
                sealed,
                transportKey: transportKey,
                clientKeyID: key.clientKeyID,
                localKeyID: key.localKeyID,
                identityID: challenge.identityID,
                pin: newPin
            )
        }
    }

    public func authenticateWithDevice(pin: String?) async throws -> OryAuthenticatedSession {
        try await withDeviceOperation {
            guard deviceAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationUnavailable
            }

            let token = try await requireSessionToken()
            let key = try await requireEnrolledKey()
            let (session, _) = try await ensureAAL2Session(sessionToken: token, key: key, pin: pin)
            return OryAuthenticatedSession(session: session)
        }
    }

    public func enrolledDevices() async throws -> [OryEnrolledDevice] {
        let token = try await requireSessionToken()
        let listing = try await deviceAuthn.listDeviceKeys(sessionToken: token)
        // Reading the store is best-effort: a device with no local key still lists the
        // identity's other devices, it just cannot mark one as "this device".
        let localKeyID = try? await deviceKeyStore.enrolledKey()?.clientKeyID
        return listing.keys.map { OryEnrolledDevice($0, currentKeyID: localKeyID ?? nil) }
    }

    public func removeDevice() async throws {
        try await withDeviceOperation {
            let key = try await requireEnrolledKey()
            try await removeDeviceKey(clientKeyID: key.clientKeyID)
        }
    }

    public func removeDevice(_ device: OryEnrolledDevice) async throws {
        try await withDeviceOperation {
            try await removeDeviceKey(clientKeyID: device.clientKeyID)
        }
    }

    /// Revokes `clientKeyID` server-side, and clears the local key when it was this device's.
    ///
    /// Removing a credential is a settings change, so the project — not this client — decides
    /// which assurance level it takes. The removal is submitted with the session at hand; only
    /// when the server asks for a second factor does the client try to supply one, and only
    /// when it can do so silently. That ordering is what makes a locked key removable: it stops
    /// counting as a second factor, so the server accepts a plain password session, whereas
    /// stepping up first would demand the PIN the user no longer has.
    private func removeDeviceKey(clientKeyID: String) async throws {
        let token = try await requireSessionToken()
        let localKey = try? await deviceKeyStore.enrolledKey()

        do {
            try await submitDeviceRemoval(clientKeyID: clientKeyID, sessionToken: token)
        } catch OryClientError.secondFactorRequired {
            // A key with no PIN proves itself with a signature alone, so step up and retry
            // rather than pushing that onto the caller. A biometric key prompts here, which is
            // appropriate for revoking a credential. A PIN key needs its PIN, so the server's
            // answer stands and the caller steps up with `authenticateWithDevice(pin:)`.
            guard let localKey, localKey.pinSecret == nil else {
                throw OryClientError.secondFactorRequired
            }
            let (_, upgraded) = try await ensureAAL2Session(sessionToken: token, key: localKey, pin: nil)
            try await submitDeviceRemoval(clientKeyID: clientKeyID, sessionToken: upgraded)
        }

        if let localKey, localKey.clientKeyID == clientKeyID {
            try await clearDeviceKey(matching: localKey)
        }
    }

    /// Creates a settings flow and submits the removal to it. The flow is bound to the session
    /// it was created with, so a retry after a step-up needs a fresh one.
    private func submitDeviceRemoval(clientKeyID: String, sessionToken: String) async throws {
        let submitURL = try await deviceAuthn.createDeviceRemovalFlow(sessionToken: sessionToken)
        try await deviceAuthn.submitDeviceRemoval(url: submitURL, sessionToken: sessionToken, clientKeyID: clientKeyID)
    }

    /// Ensures the session is at AAL2 and returns it together with the token to use for a
    /// subsequent privileged call, persisting a freshly upgraded token so later calls see it.
    /// For a PIN key `pin` supplies the required `pin_proof`; a signature-only key ignores it.
    ///
    /// The step-up runs only when the session is below AAL2: a PIN or one-step device login
    /// already lands at AAL2, and requesting an `aal=aal2` login flow with `refresh=false`
    /// while already AAL2 is rejected by the server (`session_already_available`). Shared by
    /// step-up, removal, and PIN reset.
    private func ensureAAL2Session(sessionToken: String, key: OryStoredDeviceKey, pin: String?) async throws -> (session: OrySession, token: String) {
        do {
            let current = try await session.currentSession(sessionToken: sessionToken)
            if let identityID = current.identity?.id, key.identityID != identityID {
                throw OryClientError.deviceAuthenticationEnrolledForAnotherAccount
            }
            if current.authenticatorAssuranceLevel >= .aal2 {
                return (current, sessionToken)
            }
        } catch OryClientError.secondFactorRequired {
            // The session is valid but below AAL2 — the identity now requires a second factor
            // (e.g. right after enrolling a device key). That is exactly the step-up case, not
            // a fatal error, so fall through and step up.
        }

        let stepUp = try await stepUpToAAL2(sessionToken: sessionToken, key: key, pin: pin)
        guard let upgraded = stepUp.token else {
            return (stepUp.session, sessionToken)
        }
        try await storeToken(upgraded)
        return (stepUp.session, upgraded)
    }

    /// Opens the server-sealed one-time `pin_secret`, re-protects it under `pin`, and stores the
    /// key. Shared by PIN enrollment and PIN reset, which deliver the sealed secret identically.
    private func storeSealedPIN(
        _ sealed: SealedPINSecret,
        transportKey: TransportKey,
        clientKeyID: String,
        localKeyID: String,
        identityID: String,
        pin: String
    ) async throws {
        var pinSecret = try Array(pinVault.openSealedPINSecret(
            enc: sealed.enc,
            ciphertext: sealed.ciphertext,
            transportKey: transportKey,
            clientKeyID: clientKeyID
        ))
        var pinBytes = Array(pin.utf8)
        // The vault zeroizes both the secret and the PIN as part of the seal ceremony.
        let protected = try pinVault.protect(pinSecret: &pinSecret, pin: &pinBytes)

        try await storeDeviceKey(
            OryStoredDeviceKey(
                clientKeyID: clientKeyID,
                localKeyID: localKeyID,
                pinSecret: protected,
                userVerification: .pin,
                identityID: identityID
            )
        )
    }

    /// Produces a device signature for `challenge`, gating a biometric (`.platform`) key behind
    /// the biometric prompt first. Every device signature — 1FA login, step-up, PIN rotation —
    /// flows through here, so a `.platform` key can never be signed without the gate the iOS
    /// backend trusts. A `.pin`/`.none` key signs silently.
    private func signChallenge(key: OryStoredDeviceKey, challenge: Data, reason: String) async throws -> Data {
        if key.userVerification == .platform {
            guard biometricAuthenticator.isAvailable else {
                throw OryClientError.deviceAuthenticationBiometricsUnavailable
            }
            try await biometricAuthenticator.evaluate(keyID: key.localKeyID, reason: reason)
        }
        return try await deviceAuthenticator.generateAssertion(keyID: key.localKeyID, challenge: challenge)
    }

    /// Signs an AAL2 login challenge with the enrolled key to step the session up. A PIN key
    /// must additionally prove its PIN (`pin_proof`) — the device signature alone cannot step it
    /// up — so `pin` is required for a PIN key and rejected on the server if omitted.
    private func stepUpToAAL2(sessionToken: String, key: OryStoredDeviceKey, pin: String?) async throws -> DeviceLoginOutcome {
        // Recover the pin_secret up front — a signature-only key skips this entirely
        // (empty stands for "no PIN material"; a real secret is never empty). A wrong PIN
        // is not detectable locally; it yields a wrong secret whose proof the server
        // rejects (and counts toward pin_max_attempts).
        var pinSecret: [UInt8] = []
        defer { DevicePINVault.zeroize(&pinSecret) }
        if let protected = key.pinSecret {
            guard let pin else {
                throw OryClientError.deviceAuthenticationPINRequired
            }
            var pinBytes = Array(pin.utf8)
            pinSecret = try pinVault.unlock(protected, pin: &pinBytes)
        }

        let challenge = try await deviceAuthn.createDeviceLoginChallenge(sessionToken: sessionToken)
        let signature = try await signChallenge(key: key, challenge: challenge.nonce, reason: biometricSignInReason)
        let pinProof = pinSecret.isEmpty
            ? nil
            : pinVault.proof(pinSecret: pinSecret, clientKeyID: key.clientKeyID, nonce: challenge.nonce)

        do {
            return try await deviceAuthn.submitDeviceLogin(
                url: challenge.submitURL,
                sessionToken: sessionToken,
                clientKeyID: key.clientKeyID,
                signature: signature,
                pinProof: pinProof
            )
        } catch let error as OryClientError where pinProof != nil {
            throw Self.mapPINRejection(error)
        }
    }

    /// The Ory message id the server attaches when it rejects a device-authn verifier
    /// (`ErrorValidationDeviceAuthnVerifierWrong` in `kratos/text`).
    private static let deviceAuthnVerifierWrongMessageID = 4_000_044

    /// Maps the server's rejection of a login that carried a `pin_proof` to
    /// ``OryClientError/deviceAuthenticationInvalidPIN``.
    ///
    /// The PIN is validated only by the server: a wrong PIN produces a well-formed but
    /// wrong proof, which the server rejects as a 400 validation error with message
    /// 4000044 and counts toward `pin_max_attempts`. The server deliberately renders a
    /// wrong proof, an unknown key, and a locked key identically (anti-enumeration), so on
    /// the PIN paths — where the enrolled key and signature are known good — that
    /// rejection is surfaced as an invalid PIN. Call this only when a proof was submitted.
    private static func mapPINRejection(_ error: OryClientError) -> OryClientError {
        guard case let .server(status, _, messages) = error, status == 400,
              messages.contains(where: { $0.id == deviceAuthnVerifierWrongMessageID })
        else {
            return error
        }
        return .deviceAuthenticationInvalidPIN
    }

    /// Returns the device key enrolled on this device, or throws
    /// ``OryClientError/deviceAuthenticationNotEnrolled`` when none is stored, mapping
    /// storage failures into ``OryClientError``.
    private func requireEnrolledKey() async throws -> OryStoredDeviceKey {
        let key: OryStoredDeviceKey?
        do {
            key = try await deviceKeyStore.enrolledKey()
        } catch {
            throw Self.storageError(error)
        }
        guard let key else {
            throw OryClientError.deviceAuthenticationNotEnrolled
        }
        return key
    }

    /// Throws ``OryClientError/deviceAuthenticationEnrolledForAnotherAccount`` when the stored key
    /// belongs to an identity other than `identityID`.
    private func requireNoKeyForAnotherAccount(_ identityID: String) async throws {
        let existing: OryStoredDeviceKey?
        do {
            existing = try await deviceKeyStore.enrolledKey()
        } catch {
            throw Self.storageError(error)
        }
        if let existing, existing.identityID != identityID {
            throw OryClientError.deviceAuthenticationEnrolledForAnotherAccount
        }
    }

    private func withDeviceOperation<Result: Sendable>(
        _ operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try await DeviceOperationCoordinator.shared.perform(
            scope: deviceKeyStore.deviceOperationScope,
            operation: operation
        )
    }

    private static func attestedClientKeyID(_ attestation: OryDeviceKeyAttestation) throws -> String {
        do {
            return try AttestedDeviceKeyID.derive(from: attestation.attestation)
        } catch {
            throw OryClientError.deviceAuthenticationFailed(underlying: UnderlyingError(error))
        }
    }

    /// Stores `key`, replacing any previous enrollment, and deletes the Secure Enclave
    /// sealing key of PIN material and the biometric binding the replaced record held — each
    /// enrollment creates fresh ones, so those behind the overwritten record protect nothing.
    private func storeDeviceKey(_ key: OryStoredDeviceKey) async throws {
        let previous = try? await deviceKeyStore.enrolledKey()
        do {
            try await deviceKeyStore.store(key)
        } catch {
            throw Self.storageError(error)
        }
        if let replaced = previous?.pinSecret, replaced.sealingKeyTag != key.pinSecret?.sealingKeyTag {
            pinVault.deleteSealingKey(replaced)
        }
        if let previous, previous.userVerification == .platform, previous.localKeyID != key.localKeyID {
            await biometricAuthenticator.removeEnrollment(keyID: previous.localKeyID)
        }
    }

    /// Clears the stored device key and deletes the Secure Enclave sealing key of any PIN
    /// material and the biometric binding it held. Local-only; used by removal and forget.
    private func clearDeviceKey(matching expected: OryStoredDeviceKey? = nil) async throws {
        let previous: OryStoredDeviceKey?
        if let expected {
            do {
                previous = try await deviceKeyStore.enrolledKey()
            } catch {
                throw Self.storageError(error)
            }
            guard previous == expected else { return }
        } else {
            previous = try? await deviceKeyStore.enrolledKey()
        }
        do {
            try await deviceKeyStore.clear()
        } catch {
            throw Self.storageError(error)
        }
        if let protected = previous?.pinSecret {
            pinVault.deleteSealingKey(protected)
        }
        if let previous, previous.userVerification == .platform {
            await biometricAuthenticator.removeEnrollment(keyID: previous.localKeyID)
        }
    }
}

/// A device enrollment that succeeded on the server but whose new key could not be
/// correlated locally.
private enum DeviceEnrollmentError: Error, Sendable, LocalizedError {
    case newKeyNotFound

    var errorDescription: String? {
        "The enrolled device key could not be identified in the server response."
    }
}
