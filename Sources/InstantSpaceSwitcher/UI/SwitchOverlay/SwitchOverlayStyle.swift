import AppKit

enum SwitchOverlayStyle: String, CaseIterable {
    case none
    case coreAnimation
    case edgeGlow
    case snapshotReveal

    static let defaultsKey = "switchOverlayStyle"

    static var current: SwitchOverlayStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
            let style = SwitchOverlayStyle(rawValue: rawValue)
        else {
            return .coreAnimation
        }
        return style
    }

    static func effective() -> SwitchOverlayStyle {
        let style = current
        if style == .none {
            return .none
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .coreAnimation
        }
        return style
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .coreAnimation: return "Core Animation"
        case .edgeGlow: return "Edge Glow"
        case .snapshotReveal: return "Snapshot Reveal"
        }
    }

    func makeOverlayView(frame: NSRect) -> NSView {
        switch self {
        case .none:
            return NSView(frame: frame)
        case .coreAnimation:
            return CoreAnimationOverlayView(frame: frame)
        case .edgeGlow:
            return EdgeGlowOverlayView.make(frame: frame) ?? CoreAnimationOverlayView(frame: frame)
        case .snapshotReveal:
            return SnapshotRevealOverlayView(frame: frame)
        }
    }
}
