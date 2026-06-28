import AppKit
import Combine

struct AppKeyAssignment: Codable, Equatable, Identifiable {
    var bundleIdentifier: String
    var appName: String
    var key: String

    var id: String { bundleIdentifier }

    var normalizedKey: Character? {
        key.lowercased().first
    }
}

struct WindowKeyAssignment: Equatable, Identifiable {
    var windowID: UInt32
    var bundleIdentifier: String?
    var appName: String
    var windowTitle: String
    var key: String

    var id: UInt32 { windowID }

    var targetName: String {
        windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
    }

    func matchesAppAssignment(_ assignment: AppKeyAssignment) -> Bool {
        matchesApp(bundleIdentifier: assignment.bundleIdentifier, appName: assignment.appName)
    }

    func matchesApp(bundleIdentifier otherBundleIdentifier: String?, appName otherAppName: String)
        -> Bool
    {
        if let bundleIdentifier, let otherBundleIdentifier,
            bundleIdentifier == otherBundleIdentifier
        {
            return true
        }

        return normalizedAppName(appName) == normalizedAppName(otherAppName)
    }

    private func normalizedAppName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

final class AppKeyAssignmentStore: ObservableObject {
    static let shared = AppKeyAssignmentStore()

    @Published private(set) var assignments: [AppKeyAssignment]
    @Published private(set) var windowAssignments: [WindowKeyAssignment] = []

    private let defaults: UserDefaults
    private let defaultsKey = "appKeyAssignments"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([AppKeyAssignment].self, from: data)
        {
            assignments = decoded
        } else {
            assignments = []
        }
    }

    func assignment(for bundleIdentifier: String) -> AppKeyAssignment? {
        assignments.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func assignments(for key: Character) -> [AppKeyAssignment] {
        let normalized = String(key).lowercased()
        return assignments.filter { $0.key.lowercased() == normalized }
    }

    func windowAssignments(for key: Character) -> [WindowKeyAssignment] {
        let normalized = String(key).lowercased()
        return windowAssignments.filter { $0.key.lowercased() == normalized }
    }

    func windowAssignments(for key: Character, in assignment: AppKeyAssignment)
        -> [WindowKeyAssignment]
    {
        let normalized = String(key).lowercased()
        return windowAssignments.filter {
            $0.key.lowercased() == normalized && $0.matchesAppAssignment(assignment)
        }
    }

    func hasWindowAssignments(in assignment: AppKeyAssignment) -> Bool {
        windowAssignments.contains { $0.matchesAppAssignment(assignment) }
    }

    func isAssigned(bundleIdentifier: String) -> Bool {
        assignment(for: bundleIdentifier) != nil
    }

    func appAssigned(to key: Character, excluding bundleIdentifier: String? = nil)
        -> AppKeyAssignment?
    {
        let normalized = String(key).lowercased()
        return assignments.first {
            $0.key.lowercased() == normalized && $0.bundleIdentifier != bundleIdentifier
        }
    }

    func windowAssigned(
        to key: Character,
        inAppWithBundleIdentifier bundleIdentifier: String?,
        appName: String,
        excluding windowID: UInt32? = nil
    ) -> WindowKeyAssignment? {
        let normalized = String(key).lowercased()
        return windowAssignments.first {
            $0.key.lowercased() == normalized
                && $0.windowID != windowID
                && $0.matchesApp(bundleIdentifier: bundleIdentifier, appName: appName)
        }
    }

    func setAssignment(bundleIdentifier: String, appName: String, key: Character) {
        let normalized = String(key).lowercased()
        assignments.removeAll {
            $0.bundleIdentifier == bundleIdentifier || $0.key.lowercased() == normalized
        }
        assignments.append(
            AppKeyAssignment(bundleIdentifier: bundleIdentifier, appName: appName, key: normalized)
        )
        assignments.sort {
            $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
        save()
    }

    func removeAssignment(bundleIdentifier: String) {
        assignments.removeAll { $0.bundleIdentifier == bundleIdentifier }
        save()
    }

    func setWindowAssignment(
        windowID: UInt32,
        bundleIdentifier: String?,
        appName: String,
        windowTitle: String,
        key: Character
    ) {
        let normalized = String(key).lowercased()
        windowAssignments.removeAll {
            $0.windowID == windowID
                || ($0.key.lowercased() == normalized
                    && $0.matchesApp(bundleIdentifier: bundleIdentifier, appName: appName))
        }
        windowAssignments.append(
            WindowKeyAssignment(
                windowID: windowID,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                windowTitle: windowTitle,
                key: normalized
            )
        )
        windowAssignments.sort {
            $0.targetName.localizedCaseInsensitiveCompare($1.targetName) == .orderedAscending
        }
    }

    func removeWindowAssignment(windowID: UInt32) {
        windowAssignments.removeAll { $0.windowID == windowID }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(assignments) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
