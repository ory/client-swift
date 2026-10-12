#if DEBUG
import UIKit

/// Observes every touch on the window it is attached to and reports each active
/// touch location, without ever recognizing a gesture. Because it never enters
/// the `.began`/`.recognized` state and does not cancel or delay touches, normal
/// delivery to buttons, scroll views, and text fields is left untouched.
final class TapCaptureGestureRecognizer: UIGestureRecognizer {

    /// Called on every touch phase with the current active touch locations,
    /// expressed in the coordinate space of the recognizer's view.
    var onChange: (([ObjectIdentifier: CGPoint]) -> Void)?

    private var touches = TapIndicatorState<ObjectIdentifier>()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            self.touches.began(ObjectIdentifier(touch), at: location(of: touch))
        }
        onChange?(self.touches.points)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            self.touches.moved(ObjectIdentifier(touch), to: location(of: touch))
        }
        onChange?(self.touches.points)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    /// UIKit does not deliver `touchesEnded`/`touchesCancelled` when the touch
    /// is claimed by a control it lands on; it tears the recognizer down through
    /// `reset` instead. Clearing here guarantees every marker is removed once the
    /// gesture ends, whatever path it took.
    override func reset() {
        super.reset()
        touches.clear()
        onChange?(touches.points)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            self.touches.ended(ObjectIdentifier(touch))
        }
        onChange?(self.touches.points)
        if self.touches.points.isEmpty {
            state = .failed
        }
    }

    private func location(of touch: UITouch) -> CGPoint {
        touch.location(in: view)
    }
}
#endif
