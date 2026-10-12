#if DEBUG
import UIKit

/// Draws a translucent circle at each active touch location. The view never
/// intercepts touches (`isUserInteractionEnabled` is off), so the app underneath
/// keeps receiving every gesture unchanged.
final class TapIndicatorView: UIView {

    private let diameter: CGFloat = 44
    private var markers: [ObjectIdentifier: CAShapeLayer] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reconciles the on-screen markers with the current set of active touches:
    /// new touches get a marker, moved touches are repositioned, and lifted
    /// touches fade out.
    func show(_ points: [ObjectIdentifier: CGPoint]) {
        for (id, layer) in markers where points[id] == nil {
            markers[id] = nil
            fadeOut(layer)
        }

        for (id, point) in points {
            if let layer = markers[id] {
                move(layer, to: point)
            } else {
                let layer = makeMarker(at: point)
                markers[id] = layer
                self.layer.addSublayer(layer)
            }
        }
    }

    private func makeMarker(at point: CGPoint) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.position = point
        layer.path = UIBezierPath(ovalIn: layer.bounds).cgPath
        layer.fillColor = tintColor.withAlphaComponent(0.35).cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.7).cgColor
        layer.lineWidth = 1
        return layer
    }

    private func move(_ layer: CAShapeLayer, to point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = point
        CATransaction.commit()
    }

    private func fadeOut(_ layer: CAShapeLayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.2
        layer.add(fade, forKey: "fade")
        layer.opacity = 0
        CATransaction.commit()
    }
}
#endif
