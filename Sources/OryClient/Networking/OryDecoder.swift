import Foundation
import OrySDK

/// The JSON decoder used for every Frontend API response.
///
/// Ory encodes dates as ISO 8601 strings; ``OrySDK``'s ``CodableHelper`` configures a
/// matching date strategy. Reusing it keeps `OryClient`'s decoding identical to the SDK's.
///
/// Built once and shared: constructing a `CodableHelper` allocates a `DateFormatter`, which
/// is comparatively expensive to do per response. A `JSONDecoder` is safe for concurrent
/// `decode` calls as long as its configuration is not mutated after construction (it is not),
/// and the SDK's `OpenISO8601DateFormatter`/`CodableHelper` are themselves `@unchecked Sendable`.
enum OryDecoder {
    nonisolated(unsafe) static let shared = CodableHelper().jsonDecoder
}
