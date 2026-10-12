#if DEBUG
import CoreGraphics

/// Tracks the current location of each active touch so the tap indicator can
/// draw one marker per finger. Kept free of UIKit so it can be unit tested.
struct TapIndicatorState<Touch: Hashable> {

    private(set) var points: [Touch: CGPoint] = [:]

    mutating func began(_ touch: Touch, at point: CGPoint) {
        points[touch] = point
    }

    mutating func moved(_ touch: Touch, to point: CGPoint) {
        guard points[touch] != nil else { return }
        points[touch] = point
    }

    mutating func ended(_ touch: Touch) {
        points[touch] = nil
    }

    mutating func clear() {
        points.removeAll()
    }
}
#endif
