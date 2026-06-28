import Foundation

enum EdgeGlowSettings {
    static let durationKey = "edgeGlowDuration"
    static let fadeInDurationKey = "edgeGlowFadeInDuration"
    static let fadeOutStartKey = "edgeGlowFadeOutStart"
    static let fadeOutEndKey = "edgeGlowFadeOutEnd"
    static let animateThicknessKey = "edgeGlowAnimateThickness"
    static let animateFadeKey = "edgeGlowAnimateFade"
    static let thicknessKey = "edgeGlowThickness"
    static let glowWidthKey = "edgeGlowGlowWidth"
    static let waveDensityKey = "edgeGlowWaveDensity"
    static let waveSpeedKey = "edgeGlowWaveSpeed"

    static let defaults: [String: Float] = [
        durationKey: 0.36,
        fadeInDurationKey: 0.105,
        fadeOutStartKey: 0.20,
        fadeOutEndKey: 0.34,
        thicknessKey: 5.0,
        glowWidthKey: 55.0,
        waveDensityKey: 58.0,
        waveSpeedKey: 46.0,
    ]

    static var animateThickness: Bool {
        get {
            if UserDefaults.standard.object(forKey: animateThicknessKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: animateThicknessKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: animateThicknessKey) }
    }

    static var animateFade: Bool {
        get {
            if UserDefaults.standard.object(forKey: animateFadeKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: animateFadeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: animateFadeKey) }
    }

    static func value(_ key: String) -> Float {
        let rawValue: Float
        if UserDefaults.standard.object(forKey: key) == nil {
            rawValue = defaults[key] ?? 0
        } else {
            rawValue = Float(UserDefaults.standard.double(forKey: key))
        }
        return sanitizedValue(rawValue, for: key)
    }

    static func set(_ value: Float, for key: String) {
        UserDefaults.standard.set(Double(sanitizedValue(value, for: key)), forKey: key)
    }

    private static func sanitizedValue(_ value: Float, for key: String) -> Float {
        switch key {
        case durationKey:
            return max(0.05, value)
        case fadeInDurationKey:
            return max(0.01, value)
        case fadeOutEndKey:
            return max(value, EdgeGlowSettings.value(fadeOutStartKey) + 0.01)
        case thicknessKey, glowWidthKey, waveDensityKey, waveSpeedKey:
            return max(0, value)
        default:
            return value
        }
    }

    static func resetToDefaults() {
        for (key, value) in defaults {
            UserDefaults.standard.set(Double(value), forKey: key)
        }
        animateThickness = true
        animateFade = true
    }
}
