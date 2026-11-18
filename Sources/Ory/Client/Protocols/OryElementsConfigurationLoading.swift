import Foundation

/// Loading the project's Ory Elements configuration.
public protocol OryElementsConfigurationLoading: Sendable {

    /// Loads the project settings that decide how sign-in screens look and which flows they offer.
    ///
    /// The configuration is public, so this works signed out and sends no session token. The
    /// project can change in the Ory Console at any time, so load it together with every flow you
    /// show instead of keeping it. A self-hosted Kratos has no Ory Elements configuration, so keep
    /// your screen's defaults when the call fails instead of failing the flow:
    ///
    /// ```swift
    /// async let configuration = try? client.elementsConfiguration()
    /// let loginFlow = try await client.createLoginFlow()
    ///
    /// let settings = await configuration
    /// showSignUpLink = settings.map { $0.registrationEnabled && !$0.hideRegistrationLink } ?? true
    /// ```
    ///
    /// - Returns: The project's ``OryElementsConfiguration``.
    /// - Throws: ``OryClientError/network(underlying:)`` when the server cannot be reached,
    ///   ``OryClientError/server(status:id:messages:)`` with status 404 when the project URL does
    ///   not belong to an Ory Network project, or another ``OryClientError`` on a server or
    ///   decoding failure.
    func elementsConfiguration() async throws -> OryElementsConfiguration
}
