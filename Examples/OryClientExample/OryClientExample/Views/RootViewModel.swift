import Foundation
import Observation
import OryClient

@MainActor
@Observable
final class RootViewModel {

    enum State {
        case loading
        case signedIn(OrySession)
        case needsSecondFactor
        case pinLockedRecovery(OrySession)
        case signedOut
    }

    private(set) var state: State = .loading

    /// Shared with the auth coordinator so every flow uses one configured client.
    let client: OryClientProtocol

    init(client: OryClientProtocol) {
        self.client = client
    }

    /// Reads the stored session once on launch and routes accordingly. A returning user
    /// with a valid AAL2 session goes straight in; a valid session that still needs a
    /// second factor is sent to the step-up screen; any failure shows the signed-out
    /// journey.
    func onTask() async {
        await evaluateSession()
    }

    /// Called by the auth journey once the first factor produces a session. The server
    /// does not say in the login response whether a second factor is also required (it
    /// returns an AAL1 session with no hint), so re-check before treating the user as
    /// fully signed in.
    func didAuthenticate(_ session: OrySession) async {
        await evaluateSession(fallback: session)
    }

    /// Called once the second factor completes, producing an AAL2 session.
    func didCompleteSecondFactor(_ session: OrySession) {
        state = .signedIn(session)
    }

    /// Called when the guided PIN recovery finishes — the user reset the PIN, or chose to defer.
    /// Enter the app directly without re-checking the locked state, so a user who deferred is not
    /// bounced straight back into recovery.
    func didFinishRecovery(_ session: OrySession) {
        state = .signedIn(session)
    }

    /// Re-checks the current session with the server and re-routes on the result. Use it to
    /// reflect changes made elsewhere (e.g. after a device PIN reset) or to confirm the session
    /// is still valid. Unlike ``onTask()`` it does not flash the loading state, so the caller
    /// can show an inline spinner and stay on screen.
    func refreshSession() async {
        do {
            state = .signedIn(try await client.currentSession())
        } catch OryClientError.secondFactorRequired {
            state = .needsSecondFactor
        } catch {
            state = .signedOut
        }
    }

    /// Asks the server what the current session is worth. `secondFactorRequired` means the
    /// token is valid but the project wants a second factor — route to step-up, not to
    /// sign-in.
    private func evaluateSession(fallback: OrySession? = nil) async {
        state = .loading
        do {
            state = await resolveSignedIn(try await client.currentSession())
        } catch OryClientError.secondFactorRequired {
            state = .needsSecondFactor
        } catch {
            if let fallback {
                state = await resolveSignedIn(fallback)
            } else {
                state = .signedOut
            }
        }
    }

    /// A valid first-factor session normally enters the app. But when this device's PIN is
    /// locked, route to the guided recovery step first so the user can set a new PIN. The locked
    /// state is read from the authoritative server-side device list, not from any client-side
    /// attempt counter — the login response cannot reveal it (anti-enumeration).
    private func resolveSignedIn(_ session: OrySession) async -> State {
        await currentDevicePINLocked() ? .pinLockedRecovery(session) : .signedIn(session)
    }

    /// Whether this device's key is locked after too many wrong PIN attempts. Best-effort: if the
    /// device list cannot be read (offline, or the project requires a second factor to read
    /// settings), treat the device as not locked and enter the app rather than blocking sign-in.
    private func currentDevicePINLocked() async -> Bool {
        guard let devices = try? await client.enrolledDevices() else { return false }
        return devices.contains { $0.isCurrentDevice && $0.isLocked }
    }

    /// Revokes the session server-side, clears the local token, and returns to the signed-out
    /// journey. `logout()` always clears locally, so a server failure still signs the user out
    /// on this device — the example just ignores that error and moves on.
    func signOut() async {
        try? await client.logout()
        state = .signedOut
    }
}

#if DEBUG
extension RootViewModel {
    /// A view-only fixture: `.task` evaluates the session and routes on the configured result.
    /// Set `lockedCurrentDevice` to route a signed-in session into the PIN recovery step.
    static func preview(
        _ currentSession: Result<OrySession, OryClientError>,
        lockedCurrentDevice: Bool = false
    ) -> RootViewModel {
        var client = PreviewOryClient()
        client.currentSessionResult = currentSession
        if lockedCurrentDevice {
            client.enrolledDevicesList = [PreviewData.lockedCurrentDevice()]
        }
        return RootViewModel(client: client)
    }
}
#endif
