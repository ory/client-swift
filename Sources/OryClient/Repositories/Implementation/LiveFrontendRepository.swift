import Foundation

/// The production repository for the session, login, registration, verification, recovery,
/// and settings flows.
///
/// Sends typed ``FrontendRequest``s through a ``FrontendGateway`` and maps the resulting
/// DTOs to domain models, so status handling and mapping can be unit tested with a client
/// that returns canned responses. Per-flow operations live in the `LiveFrontendRepository+*`
/// files. Device authentication is a separate repository (``LiveDeviceAuthnRepository``).
struct LiveFrontendRepository: SessionRepository, LoginRepository, RegistrationRepository, VerificationRepository, RecoveryRepository, SettingsRepository {
    let gateway: FrontendGateway
}
