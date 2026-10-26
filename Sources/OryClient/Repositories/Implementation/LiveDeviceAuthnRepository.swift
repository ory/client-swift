import Foundation
import OrySDK

/// The production ``DeviceAuthnRepository``. Kept separate from ``LiveFrontendRepository``
/// because device authentication is the largest, most involved slice of the Frontend API:
/// isolating it keeps each repository focused. Shares the transport via ``FrontendGateway``.
struct LiveDeviceAuthnRepository: DeviceAuthnRepository {

    let gateway: FrontendGateway

    func createDeviceEnrollmentChallenge(sessionToken: String) async throws -> DeviceEnrollmentChallenge {
        let response = try await gateway.send(CreateSettingsFlowRequest(sessionToken: sessionToken))
        let dto = try gateway.decoded(response)
        return DeviceEnrollmentChallenge(
            submitURL: try Self.actionURL(dto.ui.action),
            nonce: try Self.extractDeviceNonce(from: dto.ui.nodes),
            identityID: dto.identity.id
        )
    }

    func submitDeviceEnrollment(
        url submitURL: URL,
        sessionToken: String,
        attestation: Data,
        deviceName: String,
        userVerification: OryDeviceUserVerification
    ) async throws -> Set<String> {
        // No `client_key_id`: the server derives it from the attested public key.
        // `userVerification` is `.none` for a possession-only (step-up) key or `.platform` for
        // a biometric-gated key the client verifies locally; the iOS backend trusts the
        // `.platform` declaration. PIN keys are enrolled via `submitDevicePINEnrollment`.
        let update = OrySDKAPI.UpdateSettingsFlowWithDeviceAuthnMethod(
            deviceauthnRegister: .init(
                attestationIos: attestation,
                deviceName: deviceName,
                userVerification: userVerification.sdkValue,
                version: 1
            ),
            method: "deviceauthn"
        )
        let response = try await gateway.send(
            SubmitSettingsDeviceAuthnRequest(actionURL: submitURL, update: update, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return Self.extractDeviceKeyIDs(from: dto.ui.nodes)
        default:
            throw gateway.error(from: response)
        }
    }

    func createDeviceLoginChallenge(sessionToken: String) async throws -> DeviceLoginChallenge {
        let response = try await gateway.send(CreateAAL2LoginChallengeRequest(sessionToken: sessionToken))
        let dto = try gateway.decoded(response)
        return DeviceLoginChallenge(
            submitURL: try Self.actionURL(dto.ui.action),
            nonce: try Self.extractDeviceNonce(from: dto.ui.nodes)
        )
    }

    func submitDeviceLogin(
        url submitURL: URL,
        sessionToken: String,
        clientKeyID: String,
        signature: Data,
        pinProof: Data?
    ) async throws -> DeviceLoginOutcome {
        let update = OrySDKAPI.UpdateLoginFlowWithDeviceAuthnMethod(
            clientKeyId: clientKeyID,
            method: "deviceauthn",
            pinProof: pinProof,
            signature: signature
        )
        let response = try await gateway.send(
            SubmitDeviceLoginRequest(actionURL: submitURL, update: update, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return DeviceLoginOutcome(session: SessionMapper.flatMap(dto.session), token: dto.sessionToken)
        default:
            throw gateway.error(from: response)
        }
    }

    func createDeviceRemovalFlow(sessionToken: String) async throws -> URL {
        let response = try await gateway.send(CreateSettingsFlowRequest(sessionToken: sessionToken))
        let dto = try gateway.decoded(response)
        return try Self.actionURL(dto.ui.action)
    }

    func listDeviceKeys(sessionToken: String) async throws -> DeviceKeyListing {
        let response = try await gateway.send(CreateSettingsFlowRequest(sessionToken: sessionToken))
        let dto = try gateway.decoded(response)
        return DeviceKeyListing(
            submitURL: try Self.actionURL(dto.ui.action),
            keys: Self.extractDeviceKeys(from: dto.ui.nodes)
        )
    }

    func submitDeviceRemoval(url submitURL: URL, sessionToken: String, clientKeyID: String) async throws {
        let update = OrySDKAPI.UpdateSettingsFlowWithDeviceAuthnMethod(
            deviceauthnRemove: clientKeyID,
            method: "deviceauthn"
        )
        let response = try await gateway.send(
            SubmitSettingsDeviceAuthnRequest(actionURL: submitURL, update: update, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            return
        default:
            throw gateway.error(from: response)
        }
    }

    // MARK: - Passwordless 1FA (PIN and biometric)

    func submitDevicePINEnrollment(
        url submitURL: URL,
        sessionToken: String,
        attestation: Data,
        deviceName: String,
        transportPublicKey: Data
    ) async throws -> DevicePINEnrollmentResult {
        let update = OrySDKAPI.UpdateSettingsFlowWithDeviceAuthnMethod(
            deviceauthnRegister: .init(
                attestationIos: attestation,
                deviceName: deviceName,
                pinProtected: true,
                transportPublicKey: transportPublicKey,
                userVerification: .pin,
                version: 1
            ),
            method: "deviceauthn"
        )
        let response = try await gateway.send(
            SubmitSettingsDeviceAuthnRequest(actionURL: submitURL, update: update, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return DevicePINEnrollmentResult(
                keyIDs: Self.extractDeviceKeyIDs(from: dto.ui.nodes),
                sealed: try Self.extractSealedPINSecret(from: dto.continueWith)
            )
        default:
            throw gateway.error(from: response)
        }
    }

    func createDeviceFirstFactorLoginChallenge() async throws -> DeviceLoginChallenge {
        // Passwordless first factor: a fresh login flow with no session token.
        let response = try await gateway.send(CreateLoginFlowRequest())
        let dto = try gateway.decoded(response)
        return DeviceLoginChallenge(
            submitURL: try Self.actionURL(dto.ui.action),
            nonce: try Self.extractDeviceNonce(from: dto.ui.nodes)
        )
    }

    func submitDeviceFirstFactorLogin(
        url submitURL: URL,
        clientKeyID: String,
        signature: Data,
        pinProof: Data?
    ) async throws -> DeviceLoginOutcome {
        let update = OrySDKAPI.UpdateLoginFlowWithDeviceAuthnMethod(
            clientKeyId: clientKeyID,
            method: "deviceauthn",
            pinProof: pinProof,
            signature: signature
        )
        let response = try await gateway.send(
            SubmitDeviceLoginRequest(actionURL: submitURL, update: update, sessionToken: nil)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return DeviceLoginOutcome(session: SessionMapper.flatMap(dto.session), token: dto.sessionToken)
        default:
            throw gateway.error(from: response)
        }
    }

    func submitDevicePINRotation(
        url submitURL: URL,
        sessionToken: String,
        clientKeyID: String,
        signature: Data,
        transportPublicKey: Data
    ) async throws -> SealedPINSecret {
        let update = OrySDKAPI.UpdateSettingsFlowWithDeviceAuthnMethod(
            method: "deviceauthn",
            rotateSecret: .init(
                clientKeyId: clientKeyID,
                signature: signature,
                transportPublicKey: transportPublicKey
            )
        )
        let response = try await gateway.send(
            SubmitSettingsDeviceAuthnRequest(actionURL: submitURL, update: update, sessionToken: sessionToken)
        )

        switch response.status {
        case 200..<300:
            let dto = try response.success()
            return try Self.extractSealedPINSecret(from: dto.continueWith)
        default:
            throw gateway.error(from: response)
        }
    }

    // MARK: - UI node parsing

    /// Resolves a flow's `ui.action` (always an absolute URL) to a `URL`, or fails the
    /// response as unexpected when the server sends one that cannot be parsed.
    static func actionURL(_ action: String) throws -> URL {
        guard let url = URL(string: action) else {
            throw OryClientError.unexpectedResponse(underlying: ChallengeDecodingError.malformedActionURL)
        }
        return url
    }

    /// The `deviceauthn_nonce` node carries a base64-encoded `{ "nonce": "<base64>" }`
    /// envelope whose `nonce` is the raw challenge to attest.
    private struct NonceEnvelope: Decodable {
        let nonce: Data
    }

    private static func extractDeviceNonce(from nodes: [OrySDKAPI.UiNode]) throws -> Data {
        for node in nodes {
            guard case let .typeUiNodeInputAttributes(input) = node.attributes,
                  input.name == "deviceauthn_nonce",
                  case let .string(value)? = input.value
            else {
                continue
            }
            guard let envelope = Data(base64Encoded: value) else {
                throw OryClientError.unexpectedResponse(underlying: ChallengeDecodingError.malformedNonce)
            }
            do {
                return try JSONDecoder().decode(NonceEnvelope.self, from: envelope).nonce
            } catch {
                throw OryClientError.unexpectedResponse(underlying: UnderlyingError(error))
            }
        }
        throw OryClientError.deviceAuthenticationNotEnabled
    }

    /// The server lists each enrolled device key as a node labelled with
    /// `InfoSelfServiceSettingsRemoveDeviceAuthnKey` (id `1050021`), carrying the
    /// server-derived `client_key_id` in the label context. Enrollment uses this list
    /// to confirm that the locally derived fingerprint was registered.
    private static func extractDeviceKeyIDs(from nodes: [OrySDKAPI.UiNode]) -> Set<String> {
        var ids = Set<String>()
        for node in nodes {
            guard let label = node.meta.label, label.id == 1_050_021,
                  case let .dictionary(context)? = label.context,
                  case let .string(clientKeyID)? = context["client_key_id"]
            else {
                continue
            }
            ids.insert(clientKeyID)
        }
        return ids
    }

    /// The metadata the server puts in that same label context, for a "your devices" list.
    ///
    /// A node whose context cannot be read is skipped rather than failing the listing: one
    /// key the server describes in a way this build does not understand must not hide the
    /// user's other devices.
    private static func extractDeviceKeys(from nodes: [OrySDKAPI.UiNode]) -> [DeviceKeyRecord] {
        nodes.compactMap { node in
            guard let label = node.meta.label, label.id == 1_050_021, let context = label.context else {
                return nil
            }
            guard let data = try? JSONEncoder().encode(context),
                  let key = try? OryDecoder.shared.decode(DeviceKeyContext.self, from: data)
            else {
                return nil
            }
            return DeviceKeyRecord(
                clientKeyID: key.clientKeyID,
                deviceName: key.deviceName ?? "",
                createdAt: key.createdAt ?? .distantPast,
                deviceType: key.deviceType ?? "",
                state: key.state ?? "",
                userVerification: key.userVerification ?? ""
            )
        }
    }

    /// The server returns the HPKE-sealed `pin_secret` in a `continue_with` device-authn PIN
    /// entry item. Its absence means the project did not provision a PIN secret.
    private static func extractSealedPINSecret(from continueWith: [OrySDKAPI.ContinueWith]?) throws -> SealedPINSecret {
        for item in continueWith ?? [] {
            guard case let .typeContinueWithDeviceAuthnPinEntryUi(entry) = item else { continue }
            guard let enc = Data(base64Encoded: entry.data.enc),
                  let ciphertext = Data(base64Encoded: entry.data.ciphertext)
            else {
                throw OryClientError.unexpectedResponse(underlying: ChallengeDecodingError.malformedSealedSecret)
            }
            return SealedPINSecret(enc: enc, ciphertext: ciphertext)
        }
        throw OryClientError.deviceAuthenticationNotEnabled
    }
}

private extension OryDeviceUserVerification {
    /// Maps the stored/domain user-verification mode to the generated SDK enum sent on the wire.
    var sdkValue: OrySDKAPI.UserVerification {
        switch self {
        case .none: return ._none
        case .pin: return .pin
        case .platform: return .platform
        }
    }
}

/// A malformed device-authn payload in an otherwise successful response.
private enum ChallengeDecodingError: Error, LocalizedError {
    case malformedNonce
    case malformedSealedSecret
    case malformedActionURL

    var errorDescription: String? {
        switch self {
        case .malformedNonce: "The device authentication challenge could not be decoded."
        case .malformedSealedSecret: "The device authentication PIN secret could not be decoded."
        case .malformedActionURL: "The device authentication flow returned an invalid submit URL."
        }
    }
}

/// The device-key JSON the server embeds in the removal node's label context. Everything but
/// the id is optional: older keys predate some fields, and the client must still list them.
private struct DeviceKeyContext: Decodable {
    let clientKeyID: String
    let deviceName: String?
    let createdAt: Date?
    let deviceType: String?
    let state: String?
    let userVerification: String?

    enum CodingKeys: String, CodingKey {
        case clientKeyID = "client_key_id"
        case deviceName = "device_name"
        case createdAt = "created_at"
        case deviceType = "device_type"
        case state = "state"
        case userVerification = "user_verification"
    }
}
