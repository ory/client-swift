#if targetEnvironment(simulator)
import OryClient

extension OryClientConfiguration {

    /// Returns this configuration with every request sent through the completion-handler
    /// `URLSession` data task that ``OryClient`` uses below iOS 15.
    ///
    /// iOS 14 Simulator runtimes do not run on the macOS versions that current Xcode
    /// requires, so the client's iOS 14 transport cannot be tested on iOS 14 itself. Apply
    /// this on a newer Simulator to drive integration or end-to-end tests through it:
    ///
    /// ```swift
    /// #if targetEnvironment(simulator)
    /// let config = OryClientConfiguration(
    ///     projectURL: url,
    ///     deviceKeyAuthenticator: RelaxedDeviceKeyAuthenticator()
    /// ).usingLegacyDataTaskTransport()
    /// #endif
    /// ```
    ///
    /// Only the transport changes. Request building, interceptors, the network observer,
    /// and error mapping stay the same, and no other iOS 14 system behavior is emulated.
    ///
    /// Like the rest of `OryClientSimulator`, this method compiles to nothing in device
    /// builds, so a shipped app always uses the transport of the OS it runs on.
    ///
    /// - Returns: A copy of this configuration that sends requests with the iOS 14 transport.
    public func usingLegacyDataTaskTransport() -> OryClientConfiguration {
        var configuration = self
        configuration.transport = .legacyDataTask
        return configuration
    }
}
#endif
