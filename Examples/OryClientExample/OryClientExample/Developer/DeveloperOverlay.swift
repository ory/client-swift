#if DEBUG
import SwiftUI
import UIKit

extension View {
    func developerOverlay(store: NetworkHistoryStore) -> some View {
        background(DeveloperOverlayInstaller(store: store))
    }
}

private struct DeveloperOverlayInstaller: UIViewRepresentable {

    let store: NetworkHistoryStore

    func makeUIView(context: Context) -> UIView {
        let view = SceneProbeView()
        view.onWindow = { window in
            guard let scene = window.windowScene else { return }
            DeveloperOverlayController.shared.attach(to: scene, appWindow: window, store: store)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class SceneProbeView: UIView {
        var onWindow: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}

@MainActor
private final class DeveloperOverlayController {

    static let shared = DeveloperOverlayController()

    private var window: UIWindow?

    func attach(to scene: UIWindowScene, appWindow: UIWindow, store: NetworkHistoryStore) {
        guard window == nil else { return }

        let overlayController = DeveloperOverlayViewController(store: store)
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.rootViewController = overlayController
        window.isHidden = false
        self.window = window

        installTapCapture(on: appWindow, overlayController: overlayController)
    }

    private func installTapCapture(on appWindow: UIWindow, overlayController: DeveloperOverlayViewController) {
        let recognizer = TapCaptureGestureRecognizer()
        recognizer.onChange = { [weak overlayController] points in
            let enabled = UserDefaults.standard.bool(forKey: DeveloperFlags.showTapIndicator)
            overlayController?.showTapIndicator(enabled ? points : [:])
        }
        appWindow.addGestureRecognizer(recognizer)
    }
}

private final class DeveloperOverlayViewController: UIViewController {

    private let store: NetworkHistoryStore
    private let tapIndicatorView = TapIndicatorView()

    init(store: NetworkHistoryStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let passthrough = PassthroughView()
        passthrough.backgroundColor = .clear
        view = passthrough
    }

    /// Updates the tap indicator with the current active touch locations.
    func showTapIndicator(_ points: [ObjectIdentifier: CGPoint]) {
        tapIndicatorView.show(points)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tapIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tapIndicatorView)
        NSLayoutConstraint.activate([
            tapIndicatorView.topAnchor.constraint(equalTo: view.topAnchor),
            tapIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tapIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tapIndicatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let host = UIHostingController(rootView: DeveloperDotView(store: store))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            host.view.widthAnchor.constraint(equalToConstant: 44),
            host.view.heightAnchor.constraint(equalToConstant: 44),
        ])
        host.didMove(toParent: self)
    }
}

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit == self || hit == rootViewController?.view {
            return nil
        }
        return hit
    }
}

private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            let converted = subview.convert(point, from: self)
            if let hit = subview.hitTest(converted, with: event) {
                return hit
            }
        }
        return nil
    }
}

private struct DeveloperDotView: View {

    let store: NetworkHistoryStore
    @State private var isMenuPresented = false

    var body: some View {
        Button {
            isMenuPresented = true
        } label: {
            Circle()
                .fill(.tint)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("developerMenuButton")
        .accessibilityLabel("Developer tools")
        .sheet(isPresented: $isMenuPresented) {
            DeveloperMenuView(store: store)
        }
    }
}
#endif
