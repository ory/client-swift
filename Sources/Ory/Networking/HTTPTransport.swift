/// Which `URLSession` API ``URLSessionHTTPClient`` sends requests with.
package enum HTTPTransport: Sendable {

    /// Async `URLSession.data(for:)` from iOS 15, and the completion-handler bridge below it.
    case automatic

    /// The completion-handler bridge on every OS version, as below iOS 15.
    case legacyDataTask
}
