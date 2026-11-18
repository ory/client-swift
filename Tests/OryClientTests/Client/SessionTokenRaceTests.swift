import Foundation
import OryTestDoubles
import Testing
@testable import Ory

@Suite("Session token races")
struct SessionTokenRaceTests {

    /// Lets a fake's in-flight hook call back into the client it was injected into.
    private final class ClientReference: @unchecked Sendable {
        var client: OryClient?
    }

    private func makeClient(
        storage: InMemorySessionStorage,
        frontend: FakeFrontendRepository,
        reference: ClientReference,
        keyStore: InMemoryDeviceKeyStore = InMemoryDeviceKeyStore()
    ) -> OryClient {
        let client = OryClient(
            storage: storage,
            frontend: frontend,
            deviceAuthn: frontend,
            deviceKeyStore: keyStore,
            deviceAuthenticator: FakeDeviceKeyAuthenticator(),
            biometricAuthenticator: FakeBiometricAuthenticator(),
            pinSealingKeyProvider: InsecureEphemeralPINSealingKeyProvider()
        )
        reference.client = client
        return client
    }

    private static func enrolledKeyStore() -> InMemoryDeviceKeyStore {
        InMemoryDeviceKeyStore(initial: OryStoredDeviceKey(
            clientKeyID: "srv-key",
            localKeyID: "apple-key",
            userVerification: .none,
            identityID: "identity-1"
        ))
    }

    @Test("currentSession keeps a token stored by a sign-in that finished while whoami was in flight")
    func currentSessionKeepsNewerToken() async throws {
        // Given whoami rejects the old token while a sign-in stores a new one
        let storage = InMemorySessionStorage(initialToken: "ory_st_old")
        let reference = ClientReference()
        let frontend = FakeFrontendRepository(
            currentSession: .failure(.sessionExpired),
            submitLogin: .success(.success(session: Sample.session(), token: "ory_st_new")),
            duringCurrentSession: {
                _ = try await reference.client?.submitLoginFlow(
                    Sample.loginFlow(),
                    values: OryFormValues(),
                    pressing: Sample.submitAction()
                )
            }
        )
        let client = makeClient(storage: storage, frontend: frontend, reference: reference)

        // When
        await #expect {
            _ = try await client.currentSession()
        } throws: { error in
            (error as? OryClientError)?.isSessionExpired == true
        }

        // Then the new sign-in survives
        #expect(try await storage.sessionToken() == "ory_st_new")
    }

    @Test("currentSession still clears the token it sent when nothing replaced it")
    func currentSessionClearsOwnToken() async throws {
        let storage = InMemorySessionStorage(initialToken: "ory_st_old")
        let client = makeClient(
            storage: storage,
            frontend: FakeFrontendRepository(currentSession: .failure(.sessionExpired)),
            reference: ClientReference()
        )

        await #expect {
            _ = try await client.currentSession()
        } throws: { error in
            (error as? OryClientError)?.isSessionExpired == true
        }

        #expect(try await storage.sessionToken() == nil)
    }

    @Test("A step-up does not store its token after logout ran during the step-up")
    func stepUpAfterLogout() async throws {
        // Given a step-up that upgrades the same session, so the server returns the same token,
        // while the user signs out
        let storage = InMemorySessionStorage(initialToken: "ory_st_aal1")
        let reference = ClientReference()
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal1)),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal1")),
            duringDeviceLogin: { try await reference.client?.logout() }
        )
        let client = makeClient(storage: storage, frontend: frontend, reference: reference, keyStore: Self.enrolledKeyStore())

        // When / Then
        await #expect {
            _ = try await client.authenticateWithDevice()
        } throws: { error in
            (error as? OryClientError)?.isNotAuthenticated == true
        }

        // And the user stays signed out
        #expect(try await storage.sessionToken() == nil)
    }

    @Test("A step-up does not overwrite a token stored by a sign-in that finished during the step-up")
    func stepUpAfterOtherSignIn() async throws {
        let storage = InMemorySessionStorage(initialToken: "ory_st_aal1")
        let reference = ClientReference()
        let frontend = FakeFrontendRepository(
            currentSession: .success(Sample.session(assuranceLevel: .aal1)),
            submitLogin: .success(.success(session: Sample.session(), token: "ory_st_other")),
            submitDeviceLogin: .success(.fake(token: "ory_st_aal2")),
            duringDeviceLogin: {
                _ = try await reference.client?.submitLoginFlow(
                    Sample.loginFlow(),
                    values: OryFormValues(),
                    pressing: Sample.submitAction()
                )
            }
        )
        let client = makeClient(storage: storage, frontend: frontend, reference: reference, keyStore: Self.enrolledKeyStore())

        await #expect {
            _ = try await client.authenticateWithDevice()
        } throws: { error in
            (error as? OryClientError)?.isNotAuthenticated == true
        }

        #expect(try await storage.sessionToken() == "ory_st_other")
    }
}
