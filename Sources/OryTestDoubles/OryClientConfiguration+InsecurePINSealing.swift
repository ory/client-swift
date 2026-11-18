import Foundation
import Ory

public extension OryClientConfiguration {

    /// Returns a copy of this configuration that seals PIN material with in-memory software
    /// keys instead of Secure Enclave keys in the Keychain. **For tests only.**
    ///
    /// Use it where the Keychain is unavailable, most notably test runners without a host
    /// application, where creating a permanent key fails with `errSecMissingEntitlement`
    /// (-34018). The keys live for the lifetime of the process and are shared by every
    /// configuration that calls this method, the way clients on one device share the Keychain,
    /// so PIN material sealed by one client can be unsealed by another.
    ///
    /// ```swift
    /// let configuration = OryClientConfiguration(
    ///     projectURL: url,
    ///     sessionStorage: InMemorySessionStorage(),
    ///     deviceKeyStore: InMemoryDeviceKeyStore()
    /// ).usingInsecurePINSealingForTests()
    /// ```
    ///
    /// - Important: This removes the hardware protection of the PIN secret at rest. Never call
    ///   it in an app target.
    ///
    /// - Returns: A copy of this configuration that seals PIN material in memory.
    func usingInsecurePINSealingForTests() -> OryClientConfiguration {
        var configuration = self
        configuration.pinSealingKeyProvider = InsecureEphemeralPINSealingKeyProvider.shared
        return configuration
    }
}
