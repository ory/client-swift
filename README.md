# OryClient

A Swift client for [Ory](https://www.ory.sh) identity, for native iOS apps. It drives Ory's
self-service flows — sign-in, registration, email verification — and device authentication
with a PIN or Face ID / Touch ID, backed by the Secure Enclave and App Attest.

`OryClient` has no UI. It gives you flow data to render and methods to submit, so the screens
stay yours.

> **Alpha.** The public API may still change between `0.x` releases. See
> [Compatibility and stability](#compatibility-and-stability).

## Requirements

- iOS 14.0+ (or macOS 14.0+)
- Swift 6.0 / Xcode 16+
- An Ory project

For the SwiftUI example and its device-authentication setup, start with
[Example app](#example-app). The example has a higher iOS deployment target than the package.

## Installation

Add the package in Xcode (*File ▸ Add Package Dependencies…*) or in `Package.swift`:

```swift
.package(url: "https://github.com/ory/sdk-swift.git", .upToNextMinor(from: "0.1.0"))
```

Until 1.0, a minor release may contain breaking changes, so pin to the minor version:
`from: "0.1.0"` would also resolve `0.2.0`. In Xcode, set the dependency rule to
**Up to Next Minor Version**.

Then add `OryClient` to your target's dependencies.

Device authentication on a physical iOS device additionally needs **App Attest**, signing
through a paid Apple Developer Program team, and an App ID registered to that team. Configure
your Ory project's iOS App ID allow-list with `<TeamID>.<BundleID>` to bind keys to your app.
See [physical-device setup](#physical-device--apple-app-attest) for the entitlement and signing
steps. Sign-in, registration, and verification do not require App Attest.

## Getting started

Create one client and share it:

```swift
import OryClient

let ory = OryClient(configuration: OryClientConfiguration(
    projectURL: URL(string: "https://your-slug.projects.oryapis.com")!
))
```

By default the session token is stored in the Keychain, so the user stays signed in across
launches. Pass your own `OrySessionStorage` if you need different behavior.

## Signing in

Ory decides which fields a sign-in needs, so you render what the flow gives you rather than
hardcoding a form:

```swift
let flow = try await ory.createLoginFlow()

// `flow.nodes` is what to render; `flow.actions` are the buttons.
var values = flow.makeValues()
values[.identifier] = email
values[.password] = password

let action = flow.actions.first { $0.value == "password" }!

switch try await ory.submitLoginFlow(flow, values: values, pressing: action) {
case .success(let authenticated):
    // Signed in. The token is already stored.
    print(authenticated.session.identity?.id ?? "")
case .pending(let next):
    // Not done: re-render `next` — it carries the validation messages, or the next step.
    render(next)
@unknown default:
    // A result added in a later OryClient release.
    showUnsupportedStep()
}
```

`createRegistrationFlow()` / `submitRegistrationFlow(_:values:pressing:)` work the same way, as
do the verification flow methods.

Reading and ending the session:

```swift
let session = try await ory.currentSession()   // throws .notAuthenticated when signed out
try await ory.logout()                         // revokes server-side, then clears local state
```

## Device authentication

Enroll once from a signed-in session, then sign in on that device without a password.

```swift
// Check what this device can do before offering it.
if ory.availableDeviceAuthenticationMethods.contains(.pin) {
    try await ory.enrollDevice(name: UIDevice.current.name, protection: .pin(chosenPIN))
}

// On later launches:
switch try await ory.deviceEnrollment() {
case .enrolled(.pin):
    let authenticated = try await ory.loginWithDevice(pin: enteredPIN)
case .enrolled(.platform):
    let authenticated = try await ory.loginWithDevice() // Prompts for Face ID or Touch ID.
default:
    break // Show the password sign-in.
}
```

The protection you enroll with decides what the device can do. The enrolled key decides how each
call verifies the user, so the same two calls cover every protection:

| Protection at enrollment | Step up to AAL2                  | Passwordless sign-in       |
| ------------------------ | -------------------------------- | -------------------------- |
| `.none`                  | `authenticateWithDevice()`       | Not available              |
| `.pin(pin)`              | `authenticateWithDevice(pin:)`   | `loginWithDevice(pin:)`    |
| `.biometrics`            | `authenticateWithDevice()`       | `loginWithDevice()`        |

A biometric enrollment is bound to the faces or fingerprints enrolled on the device at that
moment. When one is added or removed later, biometric sign-in throws
`OryClientError.deviceAuthenticationBiometricsChanged`: sign the user in another way, call
`forgetDevice()`, and offer biometric enrollment again.

The PIN never leaves the device and is never sent to Ory: it unlocks a secret sealed in the
Secure Enclave, which produces a proof the server verifies. **The server is the only thing that
can tell you a PIN is wrong**, and it counts failed attempts — after the project's limit the key
locks. Recover with `resetDevicePIN(newPin:)`, which proves the device by its key rather than by
the old PIN.

`OryClient` does not enforce a PIN policy (length, complexity, obvious sequences). That is your
app's decision — validate before calling.

### Managing devices

An account can hold several enrolled devices, so give users a way to see and revoke them —
a lost phone should not stay able to sign in, and an account is capped at 30 enrolled keys.

```swift
for device in try await ory.enrolledDevices() {
    print(device.name, device.isCurrentDevice ? "(this device)" : "")
}

try await ory.removeDevice(lostPhone)   // revoke another device
try await ory.removeDevice()            // revoke this one
```

## Handling errors

Everything throws `OryClientError`. Match the cases you can act on, and always keep a fallback —
new cases are added as Ory grows new conditions:

```swift
do {
    try await ory.enrollDevice(name: deviceName, protection: .pin(pin))
} catch OryClientError.secondFactorRequired {
    // Valid session, but this change needs a second factor first.
} catch OryClientError.reauthenticationRequired {
    // Still signed in, but the session is too old for a privileged change. Ask again.
} catch OryClientError.flowExpired(let replacementFlowID) {
    // Flows are short-lived. Start over; `replacementFlowID` names the one Ory prepared.
} catch let OryClientError.server(status, id, messages) {
    // Anything else the server said. `id` is the stable discriminator, `messages` is
    // user-facing text you can show as-is.
    show(messages.map(\.text))
} catch {
    showGenericError()
}
```

Quick Help in Xcode documents every case, including which methods throw it.

## Testing

Depend on `OryClientProtocol`, not the concrete client, and inject the shipped stub:

```swift
import OryClientTestDoubles

let stub = OryClientStub(currentSessionResult: .failure(.sessionExpired))
let viewModel = ProfileViewModel(ory: stub)
```

`OryClientTestDoubles` also ships in-memory replacements for the Keychain-backed storage, so
tests never touch the real Keychain. On the iOS Simulator, `OryClientSimulator` provides relaxed
device attestation so device-authentication flows can be exercised without real hardware — it
compiles to nothing in device builds. Its `usingLegacyDataTaskTransport()` configuration method
runs requests through the transport the client uses on iOS 14, whose Simulator no longer runs on
current macOS versions.

## Example app

`Examples/OryClientExample` is a small SwiftUI app covering sign-in, registration, verification,
PIN and biometric enrollment, passwordless sign-in, and second-factor step-up.

### Choose where to run

**For a first run, use the iOS Simulator with a development Ory project that has relaxed
attestation enabled.** This lets you try device authentication without a paid Apple membership.

| Run destination | Attestation used by the example | Ory requirements for device authentication |
|-----------------|---------------------------------|--------------------------------------------|
| iOS Simulator (Debug or Release) | Mock, self-signed attestation from `OryClientSimulator` | Development project with **Allow relaxed attestation for testing** enabled |
| Physical iPhone (Debug or Release) | Apple App Attest | Device authentication enabled; for relaxed attestation off, use the App Attest `production` environment |

The choice is made by `#if targetEnvironment(simulator)` in
[`AppComponents.swift`](Examples/OryClientExample/OryClientExample/AppComponents.swift), **not
by `DEBUG`**. A Debug build on an iPhone uses real App Attest. The simulator implementation is
compiled out of device builds; the SDK does not fall back to it when App Attest fails.

These requirements concern device enrollment and PIN/biometric device sign-in. You can try
ordinary sign-in, registration, and verification on the Simulator without relaxed attestation.

### Common setup

1. Open [`OryClientExample.xcodeproj`](Examples/OryClientExample/OryClientExample.xcodeproj)
   in Xcode and select the `OryClientExample` scheme. The example app currently targets iOS 26.0+;
   use Xcode 26+ and a compatible Simulator runtime or device.
2. Set `projectURL` in
   [`AppConfiguration.swift`](Examples/OryClientExample/OryClientExample/AppConfiguration.swift)
   to your Ory project's public API URL. The checked-in URL is a placeholder.
3. To try device authentication, enable the `deviceauthn` method in that project. Sign in or
   register before enrolling a device. Passwordless device sign-in also requires the project's
   first-factor options (`first_factor`, and `ios_biometric_first_factor` for biometrics).

### Simulator — relaxed attestation

1. Use an Ory **development** project and enable **Allow relaxed attestation for testing**
   (`selfservice.methods.deviceauthn.config.insecure_allow_relaxed_attestation`). A project
   named "staging" does not enable this automatically. Ory Network permits this setting only
   on development projects and forces it off on production projects.
2. If the project has an iOS App ID allow-list (`ios_app_ids`), pass one of its entries to the
   simulator authenticator in `AppComponents.swift`, for example
   `RelaxedDeviceKeyAuthenticator(appID: "YOURTEAMID.com.yourcompany.OryClientExample")`.
   The example's default `RelaxedDeviceKeyAuthenticator()` supplies no App ID and works only
   when that list is empty. Relaxed attestation does **not** disable App ID checks.
3. Select an **iPhone Simulator** destination and run. No physical-device provisioning profile
   or paid Apple membership is needed. Keep normal Simulator signing enabled so the app can
   save sessions and device keys in the Keychain.

Mock keys are for testing: the backend gives them a limited lifetime and rejects them after
relaxed attestation is disabled. Enroll again on a physical device to test real attestation.

### Physical device — Apple App Attest

1. Use an Apple Developer Program membership, either individual or organization, with access
   to signing resources. Apple's free **Personal Team** does not support App Attest. The
   standard program is sufficient: neither Enterprise membership nor App Store publication
   is required. See Apple's [capability matrix](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
   and [membership details](https://developer.apple.com/support/compare-memberships/) (normally
   99 USD per year, or local pricing).
2. In the app target's **Signing & Capabilities**, enable **Automatically manage signing** and
   select your paid team. Replace the checked-in `sh.ory.OryClientExample` Bundle Identifier
   with a unique identifier registered to your team, such as `com.yourcompany.OryClientExample`.
   The project has no team set, and the checked-in identifiers are not shared signing
   credentials. If running tests on the device, configure the test targets' teams and Bundle
   Identifiers too.
3. Enable **App Attest** for that App ID and app target, and let Xcode create or update the
   provisioning profile. The app's
   [`OryClientExample.entitlements`](Examples/OryClientExample/OryClientExample/OryClientExample.entitlements)
   already sets `com.apple.developer.devicecheck.appattest-environment` to `production`.
   Keep that value when relaxed attestation is off, including for Debug builds against staging.
4. Add your actual `<TeamID>.<BundleID>` to the Ory project's
   `selfservice.methods.deviceauthn.config.ios_app_ids` allow-list. Update this entry whenever
   you change teams or Bundle Identifiers. An empty list disables App ID pinning; configure
   it to restrict device keys to your app.
5. Select a connected physical iPhone that supports App Attest, complete Xcode's device setup
   (including Developer Mode if prompted), then run and enroll the device.

Apple's App Attest `development`/`production` environment, Xcode's Debug/Release configuration,
and Ory's development/production project environment are separate settings. Apple's
`development` environment still uses real Apple attestation, but the Ory backend accepts it
only with relaxed attestation enabled. A physical device alone is therefore insufficient for
strict validation if the entitlement is set to `development`. See Apple's
[App Attest environment guide](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service).

### Troubleshooting setup

| Error or symptom | Cause and next step |
|------------------|---------------------|
| `Unable to validate the key attestation: certificate chain verification failed: x509: certificate signed by unknown authority` on the Simulator | The example sends a self-signed mock chain. Enable relaxed attestation on a development project, or follow the physical-device setup for strict validation. This is attestation validation, not an HTTPS certificate problem. |
| `Personal development teams ... do not support the App Attest capability` | The selected team is free. Select a paid team or use the Simulator route. Changing only the Bundle Identifier does not add App Attest support. |
| `Cannot create a iOS App Development provisioning profile for "sh.ory.OryClientExample"` | Read the accompanying Xcode error: check team capability support, ownership of the Bundle Identifier, and the App Attest provisioning profile. Use your own identifier and paid team for App Attest. |
| `iOS attestation was created in the development environment, which is not allowed` | Real-device attestation used Apple's `development` environment while Ory relaxed attestation is off. Set the entitlement to `production`, rebuild, and enroll a new key. |
| `App ID is not allowed` | Match the project's `ios_app_ids` entry to the signing team's `<TeamID>.<BundleID>`. On the Simulator, also pass that entry as the mock authenticator's `appID`. |

## Compatibility and stability

`OryClient` is in alpha and follows [Semantic Versioning](https://semver.org).

- **Versions.** Until 1.0, a minor release (`0.1` to `0.2`) may change or remove public API
  without a deprecation period. A patch release (`0.1.0` to `0.1.1`) contains no breaking
  changes. [CHANGELOG.md](CHANGELOG.md) lists every breaking change. From 1.0, breaking changes
  happen only in major releases.
- **Backend.** `OryClient` works with Ory Network and with self-hosted Ory Kratos from the Ory
  Enterprise License (OEL). Each release passes its end-to-end tests against the OEL Kratos
  build from the same source commit. With OEL, run a recent Kratos version. Device
  authentication is not available in open-source Ory Kratos.
- **Support for older releases.** Fixes ship in new releases only, so update to the latest
  version. Every request carries an `X-Ory-Client` header with the client version, so Ory can
  see which versions are still in use. A backend change that breaks an older release is
  announced in the changelog first.

## License

Apache 2.0. See [LICENSE](LICENSE).
