import Foundation
import Testing
@testable import OryClient

@Suite("LiveDeviceAuthnRepository")
struct LiveDeviceAuthnRepositoryTests {

    private func makeRepository(data: Data, status: Int) -> (LiveDeviceAuthnRepository, MockHTTPClient) {
        let network = MockHTTPClient(data: data, statusCode: status)
        let repository = LiveDeviceAuthnRepository(gateway: FrontendGateway(client: network))
        return (repository, network)
    }

    // MARK: - Challenge extraction

    @Test("createDeviceLoginChallenge extracts the nonce and submit URL, and requests an AAL2 flow with the token")
    func loginChallenge() async throws {
        // Given an AAL2 login flow carrying a device-authn nonce
        let (repository, network) = makeRepository(data: Fixture.loginFlowDeviceAuthn, status: 200)

        // When
        let challenge = try await repository.createDeviceLoginChallenge(sessionToken: "tok")

        // Then the nonce is decoded out of its base64 envelope and the submit URL is the action
        #expect(challenge.nonce == Data("nonce".utf8))
        #expect(challenge.submitURL.absoluteString == "https://example.com/self-service/login?flow=login-da-1")

        // And the request carried the token to an AAL2 login flow
        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
        #expect(request?.url.absoluteString.contains("aal=aal2") == true)
    }

    @Test("createDeviceFirstFactorLoginChallenge extracts the nonce without a session token")
    func firstFactorChallenge() async throws {
        let (repository, network) = makeRepository(data: Fixture.loginFlowDeviceAuthn, status: 200)

        let challenge = try await repository.createDeviceFirstFactorLoginChallenge()

        #expect(challenge.nonce == Data("nonce".utf8))
        let request = await network.lastRequest
        #expect(request?.sessionToken == nil)
    }

    @Test("createDeviceLoginChallenge throws deviceAuthenticationNotEnabled when the flow carries no nonce")
    func loginChallengeNotEnabled() async throws {
        // Given a plain login flow with no device-authn node
        let (repository, _) = makeRepository(data: Fixture.loginFlow, status: 200)

        do {
            _ = try await repository.createDeviceLoginChallenge(sessionToken: "tok")
            Issue.record("expected to throw")
        } catch OryClientError.deviceAuthenticationNotEnabled {
            // Expected.
        }
    }

    // MARK: - Login submission

    @Test("submitDeviceLogin maps a 200 to the outcome and posts to the action URL with the token")
    func submitLoginSuccess() async throws {
        let (repository, network) = makeRepository(data: Fixture.successfulLogin, status: 200)
        let action = URL(string: "https://example.com/self-service/login?flow=x")!

        let outcome = try await repository.submitDeviceLogin(
            url: action, sessionToken: "tok", clientKeyID: "key-1", signature: Data([1]), pinProof: Data([2])
        )

        #expect(outcome.session.id == "session-1")
        #expect(outcome.token == "ory_st_test")

        let request = await network.lastRequest
        #expect(request?.method == .post)
        #expect(request?.url == action)
        #expect(request?.sessionToken == "tok")
    }

    @Test("submitDeviceFirstFactorLogin maps a 200 without a session token")
    func submitFirstFactorSuccess() async throws {
        let (repository, network) = makeRepository(data: Fixture.successfulLogin, status: 200)
        let action = URL(string: "https://example.com/self-service/login?flow=x")!

        let outcome = try await repository.submitDeviceFirstFactorLogin(
            url: action, clientKeyID: "key-1", signature: Data([1]), pinProof: nil
        )

        #expect(outcome.session.id == "session-1")
        let request = await network.lastRequest
        #expect(request?.sessionToken == nil)
    }

    @Test("submitDeviceLogin maps 401 to sessionExpired")
    func submitLogin401() async throws {
        let (repository, _) = makeRepository(data: Data("{}".utf8), status: 401)

        do {
            _ = try await repository.submitDeviceLogin(
                url: URL(string: "https://example.com/l")!, sessionToken: "tok", clientKeyID: "k", signature: Data(), pinProof: nil
            )
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            #expect(error.isSessionExpired)
        }
    }

    @Test("submitDeviceLogin maps an unexpected status to a server error")
    func submitLogin500() async throws {
        let (repository, _) = makeRepository(data: Fixture.errorGeneric, status: 500)

        do {
            _ = try await repository.submitDeviceLogin(
                url: URL(string: "https://example.com/l")!, sessionToken: "tok", clientKeyID: "k", signature: Data(), pinProof: nil
            )
            Issue.record("expected to throw")
        } catch OryClientError.server(let status, _, _) {
            #expect(status == 500)
        }
    }

    @Test("a 401/403 carrying session_aal2_required maps to secondFactorRequired, not sessionExpired")
    func submitLoginSecondFactorRequired() async throws {
        // Given a 403 whose error id marks a valid session needing a second factor
        let body = Data(#"{"error":{"id":"session_aal2_required"}}"#.utf8)
        let (repository, _) = makeRepository(data: body, status: 403)

        do {
            _ = try await repository.submitDeviceLogin(
                url: URL(string: "https://example.com/l")!, sessionToken: "tok", clientKeyID: "k", signature: Data(), pinProof: nil
            )
            Issue.record("expected to throw")
        } catch OryClientError.secondFactorRequired {
            // Expected — distinct from the sessionExpired fallback.
        }
    }

    // MARK: - Settings-flow node extraction

    @Test("createDeviceEnrollmentChallenge extracts the submit URL, nonce, and existing key ids")
    func enrollmentChallenge() async throws {
        let (repository, network) = makeRepository(data: Fixture.settingsFlowDeviceAuthn, status: 200)

        let challenge = try await repository.createDeviceEnrollmentChallenge(sessionToken: "tok")

        #expect(challenge.submitURL.absoluteString == "https://example.com/self-service/settings?flow=settings-1")
        #expect(challenge.nonce == Data("nonce".utf8))

        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
        #expect(request?.url.absoluteString == "https://example.com/self-service/settings/api")
    }

    @Test("submitDeviceEnrollment returns the identity's device key ids from the flow nodes")
    func submitEnrollment() async throws {
        let (repository, _) = makeRepository(data: Fixture.settingsFlowDeviceAuthn, status: 200)

        let keyIDs = try await repository.submitDeviceEnrollment(
            url: URL(string: "https://example.com/s")!,
            sessionToken: "tok",
            attestation: Data([1]),
            deviceName: "iPhone",
            userVerification: OryDeviceUserVerification.none
        )

        #expect(keyIDs == ["key-abc"])
    }

    @Test("submitDevicePINEnrollment returns the key ids and unseals the pin secret from continue_with")
    func submitPINEnrollment() async throws {
        let (repository, _) = makeRepository(data: Fixture.settingsFlowDeviceAuthn, status: 200)

        let result = try await repository.submitDevicePINEnrollment(
            url: URL(string: "https://example.com/s")!,
            sessionToken: "tok",
            attestation: Data([1]),
            deviceName: "iPhone",
            transportPublicKey: Data([2])
        )

        #expect(result.keyIDs == ["key-abc"])
        #expect(result.sealed.enc == Data("enc".utf8))
        #expect(result.sealed.ciphertext == Data("cipher".utf8))
    }

    @Test("submitDevicePINEnrollment still finds the sealed secret past an unknown continue_with")
    func submitPINEnrollmentUnknownContinueWith() async throws {
        // The device-authn path is where the newest continue_with action has historically
        // appeared, and the PIN secret is delivered exactly once — losing this response would
        // leave a key enrolled server-side that this device can never use.
        let (repository, _) = makeRepository(data: Fixture.settingsFlowDeviceAuthnUnknownContinueWith, status: 200)

        let result = try await repository.submitDevicePINEnrollment(
            url: URL(string: "https://example.com/s")!,
            sessionToken: "tok",
            attestation: Data([1]),
            deviceName: "iPhone",
            transportPublicKey: Data([2])
        )

        #expect(result.sealed.ciphertext == Data("cipher".utf8))
    }

    @Test("listDeviceKeys reads each key's metadata out of the removal node's label context")
    func listDeviceKeys() async throws {
        // The settings flow is the only place the server exposes the key list; the metadata
        // rides in the label context of each removal node.
        let (repository, network) = makeRepository(data: Fixture.settingsFlowDeviceList, status: 200)

        let listing = try await repository.listDeviceKeys(sessionToken: "tok")

        #expect(listing.submitURL.absoluteString == "https://example.com/self-service/settings?flow=settings-1")
        #expect(listing.keys.map(\.clientKeyID) == ["key-abc", "key-locked", "key-android", "key-future"])

        let first = try #require(listing.keys.first)
        #expect(first.deviceName == "Michal's iPhone")
        #expect(first.deviceType == "iOS")
        #expect(first.userVerification == "pin")
        #expect(first.state == "confirmed")
        // Kratos timestamps carry sub-second precision; the wire decoder must accept them
        // rather than drop the key for an unreadable date.
        #expect(abs(first.createdAt.timeIntervalSince1970 - 1_785_580_200.123456) < 0.001)

        #expect(listing.keys[1].state == "locked")
        let request = await network.lastRequest
        #expect(request?.sessionToken == "tok")
    }

    // MARK: - Removal

    @Test("submitDeviceRemoval succeeds on 200 and posts to the action URL with the token")
    func removalSuccess() async throws {
        let (repository, network) = makeRepository(data: Data("{}".utf8), status: 200)
        let action = URL(string: "https://example.com/self-service/settings?flow=x")!

        try await repository.submitDeviceRemoval(url: action, sessionToken: "tok", clientKeyID: "key-1")

        let request = await network.lastRequest
        #expect(request?.method == .post)
        #expect(request?.url == action)
        #expect(request?.sessionToken == "tok")
    }

    @Test("submitDeviceRemoval maps 403 to sessionExpired")
    func removal403() async throws {
        let (repository, _) = makeRepository(data: Data("{}".utf8), status: 403)

        do {
            try await repository.submitDeviceRemoval(
                url: URL(string: "https://example.com/s")!, sessionToken: "tok", clientKeyID: "k"
            )
            Issue.record("expected to throw")
        } catch let error as OryClientError {
            #expect(error.isSessionExpired)
        }
    }
}
