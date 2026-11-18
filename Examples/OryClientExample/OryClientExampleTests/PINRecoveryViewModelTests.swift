import Foundation
import Ory
import OryTestDoubles
import Testing
@testable import OryClientExample

@MainActor
struct PINRecoveryViewModelTests {

    @Test("Given the default PIN policy, when the new PIN is a run of digits, then the reset is not sent")
    func weakPINIsNotSent() async {
        // Given
        let client = OryClientStub()
        let viewModel = makeViewModel(client: client)

        // When
        await viewModel.resetPIN("1234")

        // Then
        #expect(viewModel.errorMessage == OryClientError.pinPolicyViolation(.sequentialDigits).localizedDescription)
        #expect(await client.resetDevicePINCallCount == 0)
    }

    @Test("Given the client's own PIN policy, when the new PIN follows it, then the reset is sent")
    func customPolicyIsUsed() async {
        // Given
        let client = OryClientStub(pinPolicy: OryPINPolicy { _ in nil })
        let viewModel = makeViewModel(client: client)

        // When
        await viewModel.resetPIN("1111")

        // Then
        #expect(viewModel.errorMessage == nil)
        #expect(await client.resetDevicePINCallCount == 1)
    }

    private func makeViewModel(client: OryClientStub) -> PINRecoveryViewModel {
        PINRecoveryViewModel(
            client: client,
            session: OrySession(
                id: "recovery-session",
                isActive: true,
                expiresAt: nil,
                authenticatedAt: nil,
                authenticatorAssuranceLevel: .aal1,
                identity: OryIdentity(id: "recovery-identity", schemaID: "default")
            ),
            onRecovered: { _ in },
            onSkip: { _ in }
        )
    }
}
