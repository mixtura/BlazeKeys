import AppKit
import simd

enum EdgeGlowColorSettings {
    static let primaryRedKey = "edgeGlowPrimaryRed"
    static let primaryGreenKey = "edgeGlowPrimaryGreen"
    static let primaryBlueKey = "edgeGlowPrimaryBlue"
    static let accentRedKey = "edgeGlowAccentRed"
    static let accentGreenKey = "edgeGlowAccentGreen"
    static let accentBlueKey = "edgeGlowAccentBlue"

    private static let defaults: [String: Float] = [
        primaryRedKey: 1.0,
        primaryGreenKey: 0.42,
        primaryBlueKey: 0.05,
        accentRedKey: 1.0,
        accentGreenKey: 0.78,
        accentBlueKey: 0.18,
    ]

    static var primaryColor: NSColor {
        get {
            NSColor(
                calibratedRed: CGFloat(value(primaryRedKey)),
                green: CGFloat(value(primaryGreenKey)),
                blue: CGFloat(value(primaryBlueKey)),
                alpha: 1
            )
        }
        set { set(color: newValue, prefix: "primary") }
    }

    static var accentColor: NSColor {
        get {
            NSColor(
                calibratedRed: CGFloat(value(accentRedKey)),
                green: CGFloat(value(accentGreenKey)),
                blue: CGFloat(value(accentBlueKey)),
                alpha: 1
            )
        }
        set { set(color: newValue, prefix: "accent") }
    }

    static func primarySIMD() -> SIMD3<Float> {
        SIMD3<Float>(value(primaryRedKey), value(primaryGreenKey), value(primaryBlueKey))
    }

    static func accentSIMD() -> SIMD3<Float> {
        SIMD3<Float>(value(accentRedKey), value(accentGreenKey), value(accentBlueKey))
    }

    static func resetToDefaults() {
        for (key, value) in defaults {
            UserDefaults.standard.set(Double(value), forKey: key)
        }
    }

    private static func value(_ key: String) -> Float {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaults[key] ?? 0
        }
        return min(1, max(0, Float(UserDefaults.standard.double(forKey: key))))
    }

    private static func set(color: NSColor, prefix: String) {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        let redKey = prefix == "primary" ? primaryRedKey : accentRedKey
        let greenKey = prefix == "primary" ? primaryGreenKey : accentGreenKey
        let blueKey = prefix == "primary" ? primaryBlueKey : accentBlueKey
        UserDefaults.standard.set(Double(min(1, max(0, rgbColor.redComponent))), forKey: redKey)
        UserDefaults.standard.set(Double(min(1, max(0, rgbColor.greenComponent))), forKey: greenKey)
        UserDefaults.standard.set(Double(min(1, max(0, rgbColor.blueComponent))), forKey: blueKey)
    }
}
