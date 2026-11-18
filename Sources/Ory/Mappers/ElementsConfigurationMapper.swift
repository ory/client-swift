import Foundation
import _OryGeneratedAPI

/// Maps the project's Ory Elements configuration DTO to the domain ``OryElementsConfiguration``.
///
/// The server sends unset URLs as empty strings, so those map to `nil`.
enum ElementsConfigurationMapper: Mapper {

    typealias Failure = Never

    static func map(_ input: OrySDKAPI.ElementsConfiguration) -> Result<OryElementsConfiguration, Never> {
        .success(
            OryElementsConfiguration(
                name: input.name,
                logoLightURL: url(input.logoLightUrl),
                logoDarkURL: url(input.logoDarkUrl),
                registrationEnabled: input.registrationEnabled,
                hideRegistrationLink: input.hideRegistrationLink,
                verificationEnabled: input.verificationEnabled,
                recoveryEnabled: input.recoveryEnabled,
                termsOfServiceURL: url(input.termsOfServiceUrl),
                privacyPolicyURL: url(input.privacyPolicyUrl),
                contactURL: url(input.contactUrl),
                hideOryBranding: input.hideOryBranding
            )
        )
    }

    private static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }
}
