import AppKit
import QuartzCore

@MainActor
final class SwitchOverlayController {
    static let shared = SwitchOverlayController()

    private typealias ScreenID = UInt32

    private var windowsByScreenID: [ScreenID: SwitchOverlayWindow] = [:]
    private var styleByScreenID: [ScreenID: SwitchOverlayStyle] = [:]
    private var flashGenerationByScreenID: [ScreenID: UInt] = [:]
    private var snapshotTransitionInProgress = false

    private init() {}

    /// Captures the desktop, covers it with a snapshot overlay, switches underneath, then reveals.
    @discardableResult
    func performTransition(
        _ switchAction: @escaping () -> Bool,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        if SwitchOverlayStyle.effective() == .none {
            let result = switchAction()
            completion?(result)
            return result
        }

        if SwitchOverlayStyle.effective() == .snapshotReveal {
            if snapshotTransitionInProgress {
                completion?(false)
                return false
            }
            beginOverlayFirstSnapshotTransition(switchAction, completion: completion)
            return true
        }

        let result = switchAction()
        if result {
            flash()
        }
        completion?(result)
        return result
    }

    func flash() {
        guard SwitchOverlayStyle.effective() != .none else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            flash(on: screen, snapshot: nil)
        }
    }

    func showPrefixModeIndicator() {
        guard SwitchOverlayStyle.effective() == .edgeGlow else { return }

        for screen in NSScreen.screens {
            showPrefixModeIndicator(on: screen)
        }
    }

    func hidePrefixModeIndicator() {
        for (screenID, window) in Array(windowsByScreenID) {
            guard styleByScreenID[screenID] == .edgeGlow else { continue }
            (window.contentView as? EdgeGlowOverlayView)?.stopPrefixIndicator()
            window.orderOut(nil)
            removeWindow(window, for: screenID)
        }
    }

    /// Preview in settings: capture current desktop, hold, then play the reveal animation.
    func flashSnapshotPreview() {
        guard SwitchOverlayStyle.effective() != .none else { return }

        _ = ScreenSnapshotCapture.ensureAccess(requestIfNeeded: true)
        let snapshots = ScreenSnapshotCapture.captureScreens()
        guard !snapshots.isEmpty else { return }

        presentStaticSnapshotOverlays(snapshots)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.032) { [weak self] in
            self?.revealSnapshotOverlays()
        }
    }

    func styleDidChange() {
        flashGenerationByScreenID.removeAll()
        snapshotTransitionInProgress = false

        for (_, window) in windowsByScreenID {
            window.orderOut(nil)
        }
        windowsByScreenID.removeAll()
        styleByScreenID.removeAll()
    }

    func setStyle(_ style: SwitchOverlayStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: SwitchOverlayStyle.defaultsKey)
        styleDidChange()
    }

    private final class SpaceChangeTracker: @unchecked Sendable {
        var sawChange = false
        var lastChange = Date.distantPast
    }

    private func beginOverlayFirstSnapshotTransition(
        _ switchAction: @escaping () -> Bool,
        completion: ((Bool) -> Void)?
    ) {
        let snapshots = ScreenSnapshotCapture.captureScreensForTransition()
        guard !snapshots.isEmpty else {
            let result = switchAction()
            if result {
                flash()
            }
            completion?(result)
            return
        }

        snapshotTransitionInProgress = true

        let tracker = SpaceChangeTracker()
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            tracker.sawChange = true
            tracker.lastChange = Date()
        }

        presentStaticSnapshotOverlays(snapshots)

        CATransaction.flush()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            guard switchAction() else {
                self.finishSnapshotTransition(
                    observer: observer,
                    succeeded: false,
                    completion: completion
                )
                return
            }

            self.scheduleSpaceSettleCheck(
                tracker: tracker,
                observer: observer,
                startedAt: Date(),
                completion: completion
            )
        }
    }

    private func scheduleSpaceSettleCheck(
        tracker: SpaceChangeTracker,
        observer: NSObjectProtocol,
        startedAt: Date,
        timeout: TimeInterval = 0.5,
        quietPeriod: TimeInterval = 0.06,
        completion: ((Bool) -> Void)?
    ) {
        if tracker.sawChange && Date().timeIntervalSince(tracker.lastChange) >= quietPeriod {
            finishSnapshotTransition(observer: observer, succeeded: true, completion: completion)
            return
        }

        if Date().timeIntervalSince(startedAt) >= timeout {
            finishSnapshotTransition(observer: observer, succeeded: true, completion: completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            self?.scheduleSpaceSettleCheck(
                tracker: tracker,
                observer: observer,
                startedAt: startedAt,
                timeout: timeout,
                quietPeriod: quietPeriod,
                completion: completion
            )
        }
    }

    private func finishSnapshotTransition(
        observer: NSObjectProtocol,
        succeeded: Bool,
        completion: ((Bool) -> Void)?
    ) {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)

        if succeeded {
            revealSnapshotOverlays()
        } else {
            dismissSnapshotOverlays()
        }

        snapshotTransitionInProgress = false
        completion?(succeeded)
    }

    private func presentStaticSnapshotOverlays(_ snapshots: [ScreenID: CGImage]) {
        for screen in NSScreen.screens {
            let screenID = id(for: screen)
            guard let snapshot = snapshots[screenID] else { continue }

            let frame = alignedScreenFrame(for: screen)
            let generation = (flashGenerationByScreenID[screenID] ?? 0) &+ 1
            flashGenerationByScreenID[screenID] = generation

            let window = window(
                for: screen,
                screenID: screenID,
                style: .snapshotReveal,
                persistsAcrossSpaces: true
            )
            window.setFrame(frame, display: true)
            resetWindowVisibility(window)
            window.orderFrontRegardless()

            guard let overlayView = window.contentView as? SnapshotRevealOverlayView else {
                continue
            }
            overlayView.frame = NSRect(origin: .zero, size: frame.size)
            overlayView.setSnapshot(snapshot, backingScale: screen.backingScaleFactor)
            overlayView.showStatic()
            window.displayIfNeeded()
        }
    }

    private func alignedScreenFrame(for screen: NSScreen) -> NSRect {
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

    private func revealSnapshotOverlays() {
        for screen in NSScreen.screens {
            let screenID = id(for: screen)
            guard
                let window = windowsByScreenID[screenID],
                styleByScreenID[screenID] == .snapshotReveal,
                let overlayView = window.contentView as? SnapshotRevealOverlayView
            else {
                continue
            }

            let generation = flashGenerationByScreenID[screenID] ?? 0
            overlayView.playReveal { [weak self, weak window] in
                self?.dismissOverlayWindow(window, for: screenID, generation: generation)
            }
        }
    }

    private func dismissSnapshotOverlays() {
        for (_, window) in windowsByScreenID {
            window.orderOut(nil)
        }
        windowsByScreenID.removeAll()
        styleByScreenID.removeAll()
        flashGenerationByScreenID.removeAll()
        snapshotTransitionInProgress = false
    }

    private func showPrefixModeIndicator(on screen: NSScreen) {
        let screenID = id(for: screen)
        let generation = (flashGenerationByScreenID[screenID] ?? 0) &+ 1
        flashGenerationByScreenID[screenID] = generation

        let window = window(for: screen, screenID: screenID, style: .edgeGlow)
        window.setFrame(alignedScreenFrame(for: screen), display: true)
        resetWindowVisibility(window)
        window.orderFrontRegardless()

        guard let overlayView = window.contentView as? EdgeGlowOverlayView else { return }
        overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
        overlayView.playPrefixIndicator()
    }

    private func flash(on screen: NSScreen, snapshot: CGImage?) {
        let screenID = id(for: screen)
        let generation = (flashGenerationByScreenID[screenID] ?? 0) &+ 1
        flashGenerationByScreenID[screenID] = generation

        let style = SwitchOverlayStyle.effective()
        let resolvedStyle: SwitchOverlayStyle =
            style == .snapshotReveal && snapshot == nil ? .coreAnimation : style
        let usesSnapshot = resolvedStyle == .snapshotReveal && snapshot != nil
        let window = window(
            for: screen,
            screenID: screenID,
            style: resolvedStyle,
            persistsAcrossSpaces: usesSnapshot
        )
        window.setFrame(alignedScreenFrame(for: screen), display: true)
        resetWindowVisibility(window)
        window.orderFrontRegardless()

        if usesSnapshot, let snapshot,
            let overlayView = window.contentView as? SnapshotRevealOverlayView
        {
            overlayView.frame = NSRect(origin: .zero, size: alignedScreenFrame(for: screen).size)
            overlayView.setSnapshot(snapshot, backingScale: screen.backingScaleFactor)
            overlayView.showStatic()
            overlayView.playReveal { [weak self, weak window] in
                self?.dismissOverlayWindow(window, for: screenID, generation: generation)
            }
            return
        }

        if let overlayView = window.contentView as? SwitchOverlayRenderable {
            overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
            overlayView.play { [weak self, weak window] in
                self?.dismissOverlayWindow(window, for: screenID, generation: generation)
            }
        }
    }

    private func dismissOverlayWindow(
        _ window: SwitchOverlayWindow?,
        for screenID: ScreenID,
        generation: UInt
    ) {
        guard let window else { return }
        guard flashGenerationByScreenID[screenID] == generation else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else { return }
                guard self.flashGenerationByScreenID[screenID] == generation else { return }
                window.orderOut(nil)
                self.removeWindow(window, for: screenID)
            }
        }
    }

    private func resetWindowVisibility(_ window: SwitchOverlayWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.alphaValue = 1
        }
    }

    private func window(
        for screen: NSScreen,
        screenID: ScreenID,
        style: SwitchOverlayStyle,
        persistsAcrossSpaces: Bool = false
    ) -> SwitchOverlayWindow {
        if let window = windowsByScreenID[screenID], styleByScreenID[screenID] == style {
            return window
        }

        if let oldWindow = windowsByScreenID[screenID] {
            oldWindow.orderOut(nil)
        }

        let frame = alignedScreenFrame(for: screen)
        let window = SwitchOverlayWindow(
            frame: frame,
            persistsAcrossSpaces: persistsAcrossSpaces
        )
        window.contentView = style.makeOverlayView(
            frame: NSRect(origin: .zero, size: frame.size)
        )
        windowsByScreenID[screenID] = window
        styleByScreenID[screenID] = style
        return window
    }

    private func removeWindow(_ window: SwitchOverlayWindow, for screenID: ScreenID) {
        guard windowsByScreenID[screenID] === window else { return }
        windowsByScreenID[screenID] = nil
        styleByScreenID[screenID] = nil
        flashGenerationByScreenID[screenID] = nil
    }

    private func id(for screen: NSScreen) -> ScreenID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }
}
