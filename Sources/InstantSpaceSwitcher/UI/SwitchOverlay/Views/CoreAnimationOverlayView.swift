import AppKit
import QuartzCore

final class CoreAnimationOverlayView: NSView, SwitchOverlayRenderable {
    private let borderLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let fillLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
    }

    func play(completion: (() -> Void)?) {
        updateLayerFrames()

        borderLayer.removeAllAnimations()
        glowLayer.removeAllAnimations()
        fillLayer.removeAllAnimations()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion?()
        }
        if reduceMotion {
            playReducedMotionAnimation()
        } else {
            playOutlineAnimation()
        }
        CATransaction.commit()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true

        fillLayer.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.045).cgColor
        fillLayer.opacity = 0

        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
        glowLayer.lineWidth = 8
        glowLayer.lineJoin = .miter
        glowLayer.opacity = 0
        glowLayer.shadowColor = NSColor.systemOrange.cgColor
        glowLayer.shadowRadius = 18
        glowLayer.shadowOpacity = 0.75
        glowLayer.shadowOffset = .zero

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.systemOrange.cgColor
        borderLayer.lineWidth = 3
        borderLayer.lineJoin = .miter
        borderLayer.opacity = 0

        layer?.addSublayer(fillLayer)
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(borderLayer)
    }

    private func updateLayerFrames() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        fillLayer.frame = bounds

        let inset = borderLayer.lineWidth / 2
        let pathRect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(rect: pathRect, transform: nil)

        borderLayer.frame = bounds
        borderLayer.path = path
        glowLayer.frame = bounds
        glowLayer.path = path
    }

    private func playReducedMotionAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.opacity = 1
        glowLayer.opacity = 0.65
        fillLayer.opacity = 1
        CATransaction.commit()

        addOpacityAnimation(to: borderLayer, from: 1, to: 0, beginTime: 0.08, duration: 0.16)
        addOpacityAnimation(to: glowLayer, from: 0.65, to: 0, beginTime: 0.08, duration: 0.16)
        addOpacityAnimation(to: fillLayer, from: 1, to: 0, beginTime: 0.05, duration: 0.16)
    }

    private func playOutlineAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.opacity = 1
        borderLayer.strokeStart = 0
        borderLayer.strokeEnd = 1
        glowLayer.opacity = 0.85
        glowLayer.strokeStart = 0
        glowLayer.strokeEnd = 1
        fillLayer.opacity = 1
        CATransaction.commit()

        addOpacityAnimation(to: fillLayer, from: 1, to: 0, beginTime: 0.04, duration: 0.2)

        let stroke = CABasicAnimation(keyPath: "strokeEnd")
        stroke.fromValue = 0.25
        stroke.toValue = 1
        stroke.duration = 0.18
        stroke.timingFunction = CAMediaTimingFunction(name: .easeOut)
        borderLayer.add(stroke, forKey: "strokeEnd")
        glowLayer.add(stroke, forKey: "strokeEnd")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.018
        scale.toValue = 1
        scale.duration = 0.2
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        borderLayer.add(scale, forKey: "scale")
        glowLayer.add(scale, forKey: "scale")

        addOpacityAnimation(to: borderLayer, from: 1, to: 0, beginTime: 0.13, duration: 0.14)
        addOpacityAnimation(to: glowLayer, from: 0.85, to: 0, beginTime: 0.11, duration: 0.16)
    }

    private func addOpacityAnimation(
        to layer: CALayer,
        from fromValue: Float,
        to toValue: Float,
        beginTime: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.beginTime = CACurrentMediaTime() + beginTime
        animation.duration = duration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "opacity")
    }
}
