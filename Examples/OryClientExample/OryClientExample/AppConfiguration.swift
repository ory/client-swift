import Foundation

/// App-wide configuration for the example.
///
/// **Set ``projectURL`` to your own Ory project before running.** The value below is a
/// placeholder: the app launches with it, but every request fails until it points at a real
/// project. Find the URL in the Ory Console under your project's API endpoints — it looks like
/// `https://<your-slug>.projects.oryapis.com`.
///
/// To try the device-authentication screens, the project also needs the `deviceauthn` method
/// enabled and your app's `<TeamID>.<BundleID>` on its iOS allow-list.
enum AppConfiguration {

    // Force-unwrapped deliberately: this literal is a valid URL, so the initializer cannot
    // fail. Keep it parseable when you edit it — a placeholder like `<your-slug>` is not a
    // legal URL and would trap here at launch.
    static let projectURL = URL(string: "https://your-slug.projects.oryapis.com")!
}
