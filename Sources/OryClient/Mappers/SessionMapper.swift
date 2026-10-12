import Foundation
import OrySDK

/// Maps the generated SDK's session DTO to the domain ``OrySession``.
///
/// The DTO marks nearly every field optional. This mapper collapses the optionals
/// the server always populates into concrete values (for example `active` → ``OrySession/isActive``
/// defaults to `false`) and drops fields the domain model does not expose.
enum SessionMapper: Mapper {

    typealias Failure = Never

    static func map(_ input: OrySDKAPI.Session) -> Result<OrySession, Never> {
        let identity = input.identity.map { IdentityMapper.flatMap($0) }

        let assuranceLevel = input.authenticatorAssuranceLevel
            .flatMap { OryAuthenticatorAssuranceLevel(rawValue: $0.rawValue) } ?? .unknown

        return .success(
            OrySession(
                id: input.id,
                isActive: input.active ?? false,
                expiresAt: input.expiresAt,
                authenticatedAt: input.authenticatedAt,
                authenticatorAssuranceLevel: assuranceLevel,
                identity: identity
            )
        )
    }
}
