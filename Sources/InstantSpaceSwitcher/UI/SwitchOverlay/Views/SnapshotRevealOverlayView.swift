import AppKit
import QuartzCore

final class SnapshotRevealOverlayView: NSView, SwitchOverlayRenderable {
    private let imageView = NSImageView()
    private let gradientMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = bounds
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        gradientMask.frame = bounds
    }

    func setSnapshot(_ image: CGImage, backingScale: CGFloat? = nil) {
        let scale = backingScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        imageView.image = NSImage(cgImage: image, size: size)
    }

    func showStatic() {
        layoutSubtreeIfNeeded()
        imageView.frame = bounds
        gradientMask.removeAllAnimations()
        imageView.layer?.mask = nil
    }

    func playReveal(completion: (() -> Void)?) {
        layoutSubtreeIfNeeded()
        imageView.frame = bounds
        imageView.wantsLayer = true
        gradientMask.frame = imageView.bounds
        imageView.layer?.mask = gradientMask

        gradientMask.removeAllAnimations()

        let gradientWidth = CGFloat(
            SnapshotRevealSettings.value(SnapshotRevealSettings.gradientWidthKey))
        let duration = TimeInterval(
            SnapshotRevealSettings.value(SnapshotRevealSettings.durationKey))

        gradientMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
        ]
        gradientMask.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMask.endPoint = CGPoint(x: 1, y: 0.5)

        let startLocations: [NSNumber] = [
            NSNumber(value: -gradientWidth),
            NSNumber(value: 0),
            NSNumber(value: gradientWidth),
        ]
        let endLocations: [NSNumber] = [
            NSNumber(value: 1),
            NSNumber(value: Double(1 + gradientWidth)),
            NSNumber(value: Double(1 + 2 * gradientWidth)),
        ]

        gradientMask.locations = startLocations

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = startLocations
        animation.toValue = endLocations
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion?()
        }
        gradientMask.add(animation, forKey: "snapshotReveal")
        gradientMask.locations = endLocations
        CATransaction.commit()
    }

    func play(completion: (() -> Void)?) {
        showStatic()
        playReveal(completion: completion)
    }
}
