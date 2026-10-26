# Changelog

All notable changes to `OryClient` are documented in this file. The package follows
[Semantic Versioning](https://semver.org). Until 1.0, a minor release may contain breaking
changes.

The release workflow publishes the section whose heading matches the released version as the
GitHub release notes, so every release needs a `## <version>` section here before it runs.

## Unreleased

## 0.2.0

### Added

- Two-step registration and identifier-first login: `OryFlow.previousStepAction` goes back from the
  credential step to the profile step. Both flow styles are covered by E2E tests.
- TOTP: `OryFlow.totpSetup` gives the QR code as PNG data and the secret for linking an
  authenticator app in a settings flow, and `OryFlow.totpUnlinkAction` unlinks it.
- One-time code sign-in and registration: `OryFlow.resendCodeAction` is the "Resend code" button
  of login, registration, recovery, and verification flows. Code login and code registration are
  covered by E2E tests.
- `OryClientError.browserLocationChangeRequired(redirectURL:)` reports a method that must continue
  in a browser, such as social sign-in, with the page to open. It used to arrive as
  `.server(status: 422, …)` without the URL.
- `getLoginFlow(id:)`, `getRegistrationFlow(id:)`, and `getRecoveryFlow(id:)` fetch an existing
  flow, for example the replacement named by `OryClientError.flowExpired(replacementFlowID:)`.
  A replacement login flow is never a re-authentication; compare `OryFlow.isRefresh` before using
  it. `OryClientStub` configures their results with `getLoginFlowResult`, `getRegistrationFlowResult`,
  and `getRecoveryFlowResult`.
- Method groups: `OryInputField.group` names the method an action submits, and
  `OryFlow.availableMethods`, `nodes(in:)` and `actions(in:)` let a screen offer one method at a
  time. `OryFlow.requestedAAL` and `OryFlow.isRefresh` tell a second-factor or re-authentication
  login flow apart from a regular sign-in.
- Re-authentication and second-factor login: `OryLoginFlowOptions(refresh: true)` and
  `OryLoginFlowOptions(aal: .aal2)` start a login flow for the signed-in user. The client sends
  the stored session token when it creates and submits such a flow.
- `OryClientStub.requestedLoginFlowOptions` records the options of the last
  `createLoginFlow(options:)` call.
- A device key now belongs to the account that enrolled it. `deviceEnrollment(for:)` reports
  `.enrolledForAnotherAccount` when the device is set up for someone else, and enrolling, stepping
  up, or resetting the PIN for another account throws
  `deviceAuthenticationEnrolledForAnotherAccount` instead of replacing the other account's key.
  Call `forgetDevice()` to move device sign-in to the signed-in account.
- `OryNodeGroup`, `OryInputField.Kind`, `OryInputField.Autocomplete`, and `OryUIMessage.Kind`
  keep a value the client does not know under its wire name, for example
  `OryNodeGroup(rawValue: "future_method")`. `OryInputField.Autocomplete.usernameWebAuthn` is
  new; it used to arrive as `.username`.
- A registration response without a top-level `identity`, which Kratos sends for a restricted
  origin, no longer fails to decode. `OryRegistrationResult.identity` falls back to the session's
  identity, and `submitRegistrationFlow` throws `OryClientError.unexpectedResponse` when neither
  is present.

### Security

- Request and response interceptors receive a copy of the JSON body with credential values
  replaced by `"[REDACTED]"`: passwords, one-time codes, PIN proofs, and session tokens. The
  client still sends and decodes the original bodies.

### Breaking changes

- `OryNodeGroup.unknown` and `OryInputField.Kind.unknown` are removed. Compare with
  `init(rawValue:)` instead. `OryUIMessage.Kind.unknown` stays, for a message without a type.
- `OryEnrolledDevice.Platform` is a `RawRepresentable` struct instead of an enum.
  `.unknown("web")` becomes `OryEnrolledDevice.Platform(rawValue: "web")`.
- A request interceptor can change only headers: `OryOutgoingRequest.method`, `url`, and `body`
  are read-only. `OryResponseInterceptor.intercept(_:)` returns `Void`, and `OryReceivedResponse`
  is read-only, so a response interceptor can inspect a response or throw but not change it.

- `OryLoginFlow`, `OryRegistrationFlow`, and `OryRecoveryFlow` have a new `get…Flow(id:)`
  requirement.
- `OryStoredDeviceKey` has a required `identityID` and schema version 2. Device keys enrolled with
  0.1.0 read as not enrolled, so users enroll their device again.
- The create methods of `OryLoginFlow`, `OryRegistrationFlow`, `OryVerificationFlow`,
  `OryRecoveryFlow`, and `OrySettingsFlow` now take an options struct, for example
  `createLoginFlow(options: OryLoginFlowOptions)`. Calls such as `createLoginFlow()` keep
  working. Your own conformances to these protocols must implement the new requirements.

## 0.1.0

First public alpha release.

- Self-service flows: sign-in, registration, email verification, account recovery, and
  settings, exposed as renderable flow data (`OryFlow`, `OryNode`) with submit methods.
- Session handling with Keychain-backed session token storage by default, replaceable through
  `OrySessionStorage`.
- Device authentication with a PIN or Face ID / Touch ID, backed by the Secure Enclave and
  Apple App Attest, including device management.
- Typed errors (`OryClientError`) mapped from Ory's error responses.
- `OryClientTestDoubles`: a stub client and in-memory storage for integrators' tests.
- `OryClientSimulator`: relaxed device attestation for the iOS Simulator.
- `Examples/OryClientExample`: a SwiftUI app showing the full integration.
