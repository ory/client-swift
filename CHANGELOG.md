# Changelog

All notable changes to `OryClient` are documented in this file. The package follows
[Semantic Versioning](https://semver.org). Until 1.0, a minor release may contain breaking
changes.

The release workflow publishes the section whose heading matches the released version as the
GitHub release notes, so every release needs a `## <version>` section here before it runs.

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
