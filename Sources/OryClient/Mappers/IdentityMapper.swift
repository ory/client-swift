import Foundation
import OrySDK

/// Maps the generated SDK's identity DTO to the domain ``OryIdentity``.
///
/// Traits are schema-defined free-form JSON, so they are preserved as raw JSON for
/// the integrator to decode with ``OryIdentity/decodeTraits(as:)``.
enum IdentityMapper: Mapper {

    typealias Failure = Never

    static func map(_ input: OrySDKAPI.Identity) -> Result<OryIdentity, Never> {
        let traitsJSON: Data
        if let traits = input.traits, let encoded = try? JSONEncoder().encode(traits) {
            traitsJSON = encoded
        } else {
            traitsJSON = Data("{}".utf8)
        }

        return .success(
            OryIdentity(id: input.id, schemaID: input.schemaId, traitsJSON: traitsJSON)
        )
    }
}
