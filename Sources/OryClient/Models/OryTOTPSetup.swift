import Foundation

/// What a user needs to link an authenticator app, read from a settings flow.
///
/// Show ``qrCodePNG`` for the user to scan, and ``secret`` for typing it in by hand. Then
/// submit the six-digit code the app shows as ``OryFieldName/totpCode``, pressing the
/// ``OryNodeGroup/totp`` action:
///
/// ```swift
/// let flow = try await client.createSettingsFlow()
/// if let setup = flow.totpSetup {
///     qrImageView.image = UIImage(data: setup.qrCodePNG)
///     secretLabel.text = setup.secret
/// }
/// // After the user typed the code:
/// var values = flow.makeValues()
/// values[.totpCode] = code
/// let link = flow.actions(in: .totp).first { $0.name == .method }!
/// let result = try await client.submitSettingsFlow(flow, values: values, pressing: link)
/// ```
///
/// Linking is a privileged change. On an older session it throws
/// ``OryClientError/reauthenticationRequired``; re-authenticate with
/// `OryLoginFlowOptions(refresh: true)` and retry.
public struct OryTOTPSetup: Sendable, Hashable {

    /// The QR code that encodes the authenticator app's setup URL, as PNG data.
    public let qrCodePNG: Data

    /// The shared secret in base32, for entering it into an authenticator app by hand.
    public let secret: String

    /// Creates a TOTP setup. Provided for tests and previews.
    public init(qrCodePNG: Data, secret: String) {
        self.qrCodePNG = qrCodePNG
        self.secret = secret
    }
}
