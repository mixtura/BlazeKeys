import Foundation

enum SnapshotRevealSettings {
    static let durationKey = "snapshotRevealDuration"
    static let gradientWidthKey = "snapshotRevealGradientWidth"

    static let defaults: [String: Float] = [
        durationKey: 0.32,
        gradientWidthKey: 0.18,
    ]

    static func value(_ key: String) -> Float {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaults[key] ?? 0
        }
        return Float(UserDefaults.standard.double(forKey: key))
    }
}
