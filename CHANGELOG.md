# Changelog

All notable changes to `OryClient` are documented in this file. The package follows
[Semantic Versioning](https://semver.org). Until 1.0, a minor release may contain breaking
changes.

The release workflow publishes the section whose heading matches the released version as the
GitHub release notes, so every release needs a `## <version>` section here before it runs.

## Unreleased

## 0.3.0

This release renames the module, changes how sessions and device keys are stored in the
Keychain, and checks new PINs against a policy. Read "Upgrading from 0.2" before you update.

### Upgrading from 0.2

1. Depend on the `Ory` product and replace `import OryClient` with `import Ory`. In test targets,
   use `OryTestDoubles` and `OrySimulator` instead of `OryClientTestDoubles` and
   `OryClientSimulator`.
2. Expect every user to sign in again after the update, and to enroll the device again. The
   default Keychain stores are now scoped to `projectURL` and do not read the items 0.2 saved.
   If you pass your own Keychain stores, create them with `init(projectURL:accessGroup:)` or pass
   a `service:`.
3. Handle `OryClientError.pinPolicyViolation(_:)` where you call `enrollDevice(name:protection:)`
   with `.pin(_:)` or `resetDevicePIN(newPin:)`. Show the violation to the user, or pass your own
   policy in `OryClientConfiguration(pinPolicy:)`.
4. Handle `OryClientError.addressVerificationRequired(_:)` where you sign users in, and the new
   `OryLoginResult.verification` and `OryLoginResult.secondFactorEnrollment` after a sign-in.
5. Read the session from `OryLoginResult.session` in the result of
   `submitLoginFlow(_:values:pressing:)`.
6. Read `.text` from `OryInputField.label`, `OryNodeContent.text`, and the label of
   `OryNodeContent.link` where you showed them as a `String`.
7. Add `elementsConfiguration()` to hand-written mocks of `OryClientProtocol`.
8. In tests that run without Keychain access, call `usingInsecurePINSealingForTests()` on the
   configuration instead of passing `InsecureEphemeralPINSealingKeyProvider()`.

### Breaking changes

- The module is renamed from `OryClient` to `Ory`, so it no longer shares its name with the
  `OryClient` type. Qualified names such as `Ory.OryClientError` now resolve. Replace
  `import OryClient` with `import Ory` and depend on the `Ory` product. The client type keeps the
  name `OryClient`.
- The `OryClientTestDoubles` and `OryClientSimulator` products and modules are renamed to
  `OryTestDoubles` and `OrySimulator`.
- `OryKeychainSessionStorage` and `OryKeychainDeviceKeyStore` have no default service. Use
  `init(projectURL:accessGroup:)`, or pass your own `service:`. `OryClientConfiguration` takes
  `sessionStorage` and `deviceKeyStore` as optionals; `nil` selects the project-scoped Keychain
  stores. Existing items under the old `com.ory.client` service are not read: after updating,
  users sign in again and enroll the device again. The project-scoped stores delete those items.
- A PIN that breaks the default `OryPINPolicy`, such as `""`, `123`, `0000` or `1234`, can no
  longer be enrolled or set: the call throws `OryClientError.pinPolicyViolation(_:)`. Handle the
  new `OryClientError` case, or pass your own policy in `OryClientConfiguration(pinPolicy:)`.
  `OryDeviceEnrollment` has a new `pinPolicy` requirement with a default implementation.
- `submitLoginFlow(_:values:pressing:)` returns `OryFlowResult<OryLoginResult>` instead of
  `OryFlowResult<OryAuthenticatedSession>`. `OryLoginResult.session` replaces
  `OryAuthenticatedSession.session`.
- `OryInputField.label` is an `OryUIMessage?`, and `OryNodeContent.text` and the label of
  `OryNodeContent.link` are `OryUIMessage`, instead of `String`. They keep the message id and its
  `context`, so an app can show its own translation. Read `.text` where you showed the string.
- `currentSession()` no longer signs the user out on a 401 or 403 it does not recognize. Only a
  401 without an error id or with `session_inactive` is `OryClientError.sessionExpired` and clears
  the stored token. Any other 401 or 403, including one from a proxy in front of Ory, arrives as
  `OryClientError.server(status:id:messages:)` and the token is kept. `logout()` still treats a
  token the server does not know as an already-completed logout.
- `OryClientProtocol` requires `elementsConfiguration()`, through the new
  `OryElementsConfigurationLoading` protocol. Hand-written mocks of `OryClientProtocol` need it.
- `OryPINSealingKeyProvider`, `OrySecureEnclavePINSealingKeyProvider`, and the
  `pinSealingKeyProvider` parameter of `OryClientConfiguration` are no longer public: PIN
  material is always sealed with the Secure Enclave. Tests that ran without Keychain access call
  `usingInsecurePINSealingForTests()` from `OryTestDoubles` on the configuration instead of
  passing `InsecureEphemeralPINSealingKeyProvider()`.
- `OryFieldName.lookupSecret` and `OryFieldName.provider` are removed: OryClient does not complete
  backup codes or social sign-in. The README lists the supported methods, and the docs of the
  `OryNodeGroup` constants for the other methods say to hide their actions.

### Security

- The default session token and device key Keychain items are scoped to `projectURL`: its
  scheme, host, port, and path. Clients configured for different Ory projects in one app keep
  separate sessions and device keys.
- `enrollDevice(name:protection:)` with `.pin(_:)` and `resetDevicePIN(newPin:)` check the PIN
  against `OryClientConfiguration.pinPolicy` before sending anything, and throw
  `OryClientError.pinPolicyViolation(_:)` for a PIN that breaks it. The default,
  `OryPINPolicy.default`, accepts 4 to 32 characters and rejects a PIN that repeats one character
  (`1111`) or is a run of consecutive digits (`1234`, `9876`). Pass your own `OryPINPolicy` to
  replace it. Read the client's policy from `pinPolicy` to check a PIN while the user types.
  Signing in and stepping up with an existing PIN are not checked.

### Added

- `OryFlow.makeValues(keeping:)` fills the values of the next step or of a replacement flow with
  what the user typed into the earlier one. It clears passwords and one-time codes, drops values
  of inputs the new flow no longer has, and keeps the server's prefilled value where the user left
  an input empty.
- `OryNode.inputField` is the node's input, or `nil` for text, images and links, so reading a
  field no longer needs a `case let .input(field)` match.
- `OryClient.elementsConfiguration()` loads the project's Ory Elements configuration as
  `OryElementsConfiguration`: its name and logos, which flows it allows, whether the sign-up link
  and the Ory badge show, and its legal links. It works signed out. `OryClientStub` returns a
  configured value.
- `OryFlow.firstFactorDeviceMethods` lists the device keys that can sign in without a password in
  a login or settings flow: `.pin`, and `.biometric` only when the project allows biometric keys
  as a first factor. Offer `loginWithDevice(pin:)` signed out only for a listed method.
- `OryFlow.activeMethod` and `OryFlow.state` report the method the user is in the middle of and
  the step the flow is at, for example `.code` and `.sentEmail` after Ory emailed a one-time
  code. `OryFlow.submittedIdentifier` is the identifier entered on the first step of an
  identifier-first login, once the flow is past it.
- `OryFlow`, `OryAuthenticatedSession`, the five flow results and `OryFormValues` are `Hashable`,
  and `OryFlowResult` is where its result is. `OryClientError` is `Equatable`; an underlying error
  compares by its `NSError` domain and code. Use them with `onChange(of:)`, navigation paths and
  test assertions.
- `OryErrorID.sessionCredentialRequired` names the 403 Ory returns when a session must sign in
  with a specific credential first, for example to link a sign-in method.
- `OryLoginResult.verification` and `OryLoginResult.secondFactorEnrollment` name the step a
  project asks for after sign-in: an address to verify, or a settings flow to add a required
  second factor. Covered by E2E tests.
- `OryClientError.addressVerificationRequired(_:)` carries the verification flow when the project
  refuses to sign in an unverified address. It used to arrive as `.server(status: 403, …)` without
  the flow. Covered by E2E tests.

### Fixed

- Submitting a recovery flow that can no longer take the submission, for example sending a used
  code again, returns `.pending` with the replacement flow the server created and its message.
  It used to throw an error.
- A sign-in that finishes while `currentSession()` waits for the server is no longer signed out
  when the server rejects the previous token. Only the rejected token is cleared.
- A device step-up that finishes after `logout()` or after another sign-in no longer stores its
  token. `authenticateWithDevice(pin:)` and `removeDevice(_:)` throw
  `OryClientError.notAuthenticated` instead.

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
