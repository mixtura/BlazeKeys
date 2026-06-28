import AppKit
import CoreGraphics

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

enum ScreenSnapshotCapture {
    typealias ScreenID = UInt32

    static func ensureAccess(requestIfNeeded: Bool = true) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard requestIfNeeded else {
            return false
        }
        return CGRequestScreenCaptureAccess()
    }

    static func captureScreens() -> [ScreenID: CGImage] {
        guard ensureAccess(requestIfNeeded: true) else {
            return [:]
        }

        if #available(macOS 14.0, *) {
            let screenCaptureKitSnapshots = captureWithScreenCaptureKit()
            if !screenCaptureKitSnapshots.isEmpty {
                return screenCaptureKitSnapshots
            }
        }

        return captureWithWindowList()
    }

    /// Prefer the synchronous window-list path for low-latency transition covers.
    static func captureScreensForTransition() -> [ScreenID: CGImage] {
        guard ensureAccess(requestIfNeeded: true) else {
            return [:]
        }

        let windowListSnapshots = captureWithWindowList()
        if !windowListSnapshots.isEmpty {
            return windowListSnapshots
        }

        if #available(macOS 14.0, *) {
            return captureWithScreenCaptureKit()
        }

        return [:]
    }

    private static func captureWithWindowList() -> [ScreenID: CGImage] {
        var snapshots: [ScreenID: CGImage] = [:]

        for screen in NSScreen.screens {
            let screenID = screenID(for: screen)
            let captureFrame = captureFrame(for: screen)
            guard
                let image = CGWindowListCreateImage(
                    captureFrame,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                )
            else {
                continue
            }

            snapshots[screenID] = image
        }

        return snapshots
    }

    @available(macOS 14.0, *)
    private static func captureWithScreenCaptureKit() -> [ScreenID: CGImage] {
        var snapshots: [ScreenID: CGImage] = [:]
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                for display in content.displays {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.captureResolution = .best
                    configuration.width = display.width
                    configuration.height = display.height
                    configuration.showsCursor = false

                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: configuration
                    )
                    snapshots[display.displayID] = image
                }
            } catch {
                print("[ScreenSnapshotCapture] ScreenCaptureKit capture failed: \(error)")
            }
        }

        semaphore.wait()
        return snapshots
    }

    private static func screenID(for screen: NSScreen) -> ScreenID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }

    private static func captureFrame(for screen: NSScreen) -> CGRect {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
        {
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            if displayID != 0 {
                return CGDisplayBounds(displayID)
            }
        }
        return screen.frame
    }
}
