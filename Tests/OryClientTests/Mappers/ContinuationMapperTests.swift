import Foundation
import Testing
import _OryGeneratedAPI
@testable import Ory

@Suite("ContinuationMapper")
struct ContinuationMapperTests {

    /// The `continue_with` items Kratos sends to native flows, in its wire shapes.
    enum Item {
        static let sessionToken = #"{"action":"set_ory_session_token","ory_session_token":"ory_st_recovered"}"#
        static let verification = #"{"action":"show_verification_ui","flow":{"id":"verification-1","verifiable_address":"alice@example.com","url":""}}"#
        static let settings = #"{"action":"show_settings_ui","flow":{"id":"settings-1","url":"https://example.com/settings?flow=settings-1"}}"#
        static let recovery = #"{"action":"show_recovery_ui","flow":{"id":"recovery-2"}}"#
        static let redirect = #"{"action":"redirect_browser_to","redirect_browser_to":"https://example.com/welcome"}"#
        static let pinEntry = #"{"action":"show_pin_entry_ui","data":{"enc":"ZW5j","ciphertext":"Y2lwaGVy"}}"#
        static let future = #"{"action":"show_something_new","flow":{"id":"x"}}"#
    }

    private func map(_ items: String...) throws -> FlowContinuation {
        let json = "[\(items.joined(separator: ","))]"
        let decoded = try JSONDecoder().decode([OrySDKAPI.ContinueWith].self, from: Data(json.utf8))
        return ContinuationMapper.map(decoded)
    }

    @Test("Every native item type maps to its next step")
    func mapsEveryItem() throws {
        let continuation = try map(Item.sessionToken, Item.verification, Item.settings, Item.recovery)

        #expect(continuation.sessionToken == "ory_st_recovered")
        #expect(continuation.verification == OryVerificationHandle(flowID: "verification-1", address: "alice@example.com"))
        #expect(continuation.settings == OrySettingsHandle(flowID: "settings-1"))
        #expect(continuation.recoveryFlowID == "recovery-2")
    }

    @Test("Browser redirects, device PIN entry, and unknown items are skipped")
    func skipsOtherItems() throws {
        let continuation = try map(Item.redirect, Item.pinEntry, Item.future)

        #expect(continuation == FlowContinuation())
    }

    @Test("A missing or empty list has no next step")
    func emptyList() {
        #expect(ContinuationMapper.map(nil) == FlowContinuation())
        #expect(ContinuationMapper.map([]) == FlowContinuation())
    }
}
