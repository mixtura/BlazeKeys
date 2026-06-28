import AppKit
import Carbon
import ISS

final class RightCommandWindowSwitcher {
    static let shared = RightCommandWindowSwitcher()

    private struct Candidate {
        let windowID: UInt32
        let ownerPID: pid_t
        let ownerName: String
        let title: String
        let bundleIdentifier: String?

        var displayName: String {
            title.isEmpty ? ownerName : title
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightCommandDown = false
    private var leftCommandDown = false
    private var lastRefresh = Date.distantPast
    private var cachedCandidates: [Candidate] = []
    private var activePrefixAssignment: AppKeyAssignment?
    private var lastCycleCharacter: Character?
    private var lastCycleWindowIDs: [UInt32] = []
    private var lastCycleIndex = 0
    private var lastCycleDate = Date.distantPast
    private let cacheDuration: TimeInterval = 0.35
    private let cycleDuration: TimeInterval = 1.2

    private var debugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "rightCommandWindowSwitchingDebug")
    }

    private init() {}

    var isRunning: Bool {
        eventTap != nil
    }

    func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            debug("not starting: Accessibility permission is not granted")
            return
        }

        let mask =
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let switcher = Unmanaged<RightCommandWindowSwitcher>.fromOpaque(userInfo)
                        .takeUnretainedValue()

                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let eventTap = switcher.eventTap {
                            CGEvent.tapEnable(tap: eventTap, enable: true)
                        }
                        return Unmanaged.passUnretained(event)
                    }

                    return switcher.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            debug("failed to create event tap")
            return
        }

        debug("started event tap")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        rightCommandDown = false
        leftCommandDown = false
        cachedCandidates.removeAll()
        resetCycleState()
        debug("stopped event tap")
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            updateCommandState(from: event)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            guard rightCommandDown && !leftCommandDown else {
                return Unmanaged.passUnretained(event)
            }

            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                return Unmanaged.passUnretained(event)
            }

            guard let character = firstLetter(from: event) else {
                return Unmanaged.passUnretained(event)
            }

            if event.flags.contains(.maskAlternate) {
                debug("RightCmd + Option + \(character)")
                exitPrefixMode()
                assignCurrentWindow(to: character)
                return nil
            }

            if let prefixAssignment = activePrefixAssignment {
                debug("RightCmd prefix \(prefixAssignment.appName) + \(character)")
                exitPrefixMode()
                return handlePrefixKey(character, in: prefixAssignment)
                    ? nil : Unmanaged.passUnretained(event)
            }

            if character == "q" {
                debug("RightCmd + Q")
                quitApplication()
                return nil
            }

            debug("RightCmd + \(character)")
            if switchToFirstWindow(startingWith: character) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func updateCommandState(from event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == kVK_RightCommand {
            rightCommandDown.toggle()
            debug("right command \(rightCommandDown ? "down" : "up")")
        } else if keyCode == kVK_Command {
            leftCommandDown.toggle()
            debug("left command \(leftCommandDown ? "down" : "up")")
        }

        if !event.flags.contains(.maskCommand) {
            rightCommandDown = false
            leftCommandDown = false
        }

        if !rightCommandDown {
            exitPrefixMode()
        }
    }

    private func firstLetter(from event: CGEvent) -> Character? {
        guard let nsEvent = NSEvent(cgEvent: event),
            let characters = nsEvent.charactersIgnoringModifiers?.lowercased(),
            let first = characters.first,
            first.isLetter || first.isNumber
        else {
            return nil
        }

        return first
    }

    private func switchToFirstWindow(startingWith character: Character) -> Bool {
        let candidates = windowCandidates()
        debug("candidate count: \(candidates.count)")

        let appAssignments = AppKeyAssignmentStore.shared.assignments(for: character)
        if let appAssignment = appAssignments.first {
            let scopedWindowCount = AppKeyAssignmentStore.shared.windowAssignments.filter {
                $0.matchesAppAssignment(appAssignment)
            }.count
            debug(
                "app assignment \(appAssignment.appName) has \(scopedWindowCount) scoped window assignment(s)"
            )
            if scopedWindowCount > 0 {
                enterPrefixMode(for: appAssignment)
                return true
            }
            return switchToAppAssignedWindow(
                appAssignments, candidates: candidates, character: character)
        }

        if let autoAssignment = autoAppPrefixAssignment(
            startingWith: character, candidates: candidates)
        {
            enterPrefixMode(for: autoAssignment)
            return true
        }

        let windowAssignments = AppKeyAssignmentStore.shared.windowAssignments(for: character)
        if !windowAssignments.isEmpty {
            return switchToAssignedWindow(
                windowAssignments, candidates: candidates, character: character)
        }

        let matches = candidates.filter { candidateMatches($0, character: character) }
        guard !matches.isEmpty else {
            debug("no candidate for \(character)")
            resetCycleState()
            return false
        }

        let candidate = candidateToFocus(from: matches, character: character)
        debug(
            "matched windowID=\(candidate.windowID) app=\(candidate.ownerName) title=\(candidate.title) cycleIndex=\(lastCycleIndex + 1)/\(matches.count)"
        )
        performWindowSpaceSwitchWithOverlay(candidate: candidate)
        return true
    }

    private func assignCurrentWindow(to character: Character) {
        let store = AppKeyAssignmentStore.shared
        guard let candidate = currentWindowCandidate() else {
            debug("no current window candidate to assign")
            DispatchQueue.main.async {
                NSSound.beep()
                OSDWindow.shared.show(message: "No active window")
            }
            return
        }

        store.setWindowAssignment(
            windowID: candidate.windowID,
            bundleIdentifier: candidate.bundleIdentifier,
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            key: character
        )

        resetCycleState()
        showSwitchOverlay()
        DispatchQueue.main.async {
            OSDWindow.shared.show(
                message: "\(String(character).uppercased()) → \(candidate.displayName)"
            )
        }
    }

    private func currentWindowCandidate() -> Candidate? {
        let candidates = enumerateWindowCandidates(
            options: [.optionOnScreenOnly, .excludeDesktopElements]
        )
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return candidates.first
        }

        let frontmostCandidates = candidates.filter { $0.ownerPID == frontmostPID }
        guard !frontmostCandidates.isEmpty else { return nil }

        let focusedTitle = focusedWindowTitle(for: frontmostPID)
        if !focusedTitle.isEmpty,
            let matching = frontmostCandidates.first(where: { $0.title == focusedTitle })
        {
            return matching
        }

        // CGWindowListCopyWindowInfo with .optionOnScreenOnly is ordered front-to-back.
        return frontmostCandidates.first
    }

    private func focusedWindowTitle(for pid: pid_t) -> String {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedWindowValue
            ) == .success,
            let focusedWindow = focusedWindowValue
        else {
            return ""
        }

        var titleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focusedWindow as! AXUIElement,
                kAXTitleAttribute as CFString,
                &titleValue
            ) == .success
        else {
            return ""
        }

        return (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func windowCandidates() -> [Candidate] {
        let now = Date()
        if now.timeIntervalSince(lastRefresh) < cacheDuration {
            return cachedCandidates
        }

        lastRefresh = now
        cachedCandidates = enumerateWindowCandidates(options: [.optionAll, .excludeDesktopElements])
        return cachedCandidates
    }

    private func enumerateWindowCandidates(options: CGWindowListOption) -> [Candidate] {
        guard
            let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            debug("CGWindowListCopyWindowInfo returned nil")
            return []
        }

        debug("CG window count: \(infoList.count)")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var seenWindowIDs = Set<UInt32>()
        var candidates: [Candidate] = []

        var layerZeroWindowCount = 0
        var spaceMappedWindowCount = 0

        for info in infoList {
            guard let layer = numberValue(info[kCGWindowLayer as String])?.intValue, layer == 0,
                let ownerPIDNumber = numberValue(info[kCGWindowOwnerPID as String]),
                let windowNumberNumber = numberValue(info[kCGWindowNumber as String])
            else {
                continue
            }

            layerZeroWindowCount += 1
            let ownerPID = pid_t(ownerPIDNumber.int32Value)
            let windowNumber = windowNumberNumber.uint32Value
            guard ownerPID != currentPID, !seenWindowIDs.contains(windowNumber) else {
                continue
            }

            if let alpha = numberValue(info[kCGWindowAlpha as String])?.doubleValue, alpha <= 0 {
                continue
            }

            if let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width <= 1 || bounds.height <= 1
            {
                continue
            }

            var spaceInfo = ISSWindowSpaceInfo()
            guard iss_get_window_space_info(windowNumber, &spaceInfo) else {
                continue
            }
            spaceMappedWindowCount += 1

            let ownerName =
                (info[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
            let title =
                (info[kCGWindowName as String] as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
            guard !ownerName.isEmpty || !title.isEmpty else {
                continue
            }

            seenWindowIDs.insert(windowNumber)
            let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?
                .bundleIdentifier
            candidates.append(
                Candidate(
                    windowID: windowNumber,
                    ownerPID: ownerPID,
                    ownerName: ownerName,
                    title: title,
                    bundleIdentifier: bundleIdentifier
                )
            )
        }

        debug(
            "layer-0 windows: \(layerZeroWindowCount), space-mapped windows: \(spaceMappedWindowCount), usable candidates: \(candidates.count)"
        )
        return candidates
    }

    private func numberValue(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private func candidateToFocus(from matches: [Candidate], character: Character) -> Candidate {
        let windowIDs = matches.map(\.windowID)
        let now = Date()
        let shouldContinueCycle =
            lastCycleCharacter == character
            && lastCycleWindowIDs == windowIDs
            && now.timeIntervalSince(lastCycleDate) <= cycleDuration

        if shouldContinueCycle {
            lastCycleIndex = (lastCycleIndex + 1) % matches.count
        } else {
            lastCycleCharacter = character
            lastCycleWindowIDs = windowIDs
            lastCycleIndex = 0
        }

        lastCycleDate = now
        return matches[lastCycleIndex]
    }

    private func resetCycleState() {
        lastCycleCharacter = nil
        lastCycleWindowIDs = []
        lastCycleIndex = 0
        lastCycleDate = .distantPast
    }

    private func autoAppPrefixAssignment(
        startingWith character: Character,
        candidates: [Candidate]
    ) -> AppKeyAssignment? {
        var seenScopes = Set<String>()
        for candidate in candidates
        where firstComparableCharacter(in: candidate.ownerName) == character {
            let scopeID =
                candidate.bundleIdentifier ?? "name:\(normalizedAppName(candidate.ownerName))"
            guard !seenScopes.contains(scopeID) else { continue }
            seenScopes.insert(scopeID)

            let assignment = AppKeyAssignment(
                bundleIdentifier: candidate.bundleIdentifier ?? scopeID,
                appName: candidate.ownerName,
                key: String(character)
            )
            let scopedWindowCount = AppKeyAssignmentStore.shared.windowAssignments.filter {
                $0.matchesAppAssignment(assignment)
            }.count
            debug(
                "auto app assignment \(candidate.ownerName) has \(scopedWindowCount) scoped window assignment(s)"
            )
            if scopedWindowCount > 0 {
                return assignment
            }
        }
        return nil
    }

    private func enterPrefixMode(for assignment: AppKeyAssignment) {
        activePrefixAssignment = assignment
        resetCycleState()
        debug("entered prefix mode for \(assignment.appName)")
        Task { @MainActor in
            SwitchOverlayController.shared.showPrefixModeIndicator()
            OSDWindow.shared.show(message: "\(assignment.appName): window key")
        }
    }

    private func exitPrefixMode() {
        guard activePrefixAssignment != nil else { return }
        debug("exited prefix mode")
        activePrefixAssignment = nil
        Task { @MainActor in
            SwitchOverlayController.shared.hidePrefixModeIndicator()
        }
    }

    private func handlePrefixKey(_ character: Character, in assignment: AppKeyAssignment) -> Bool {
        let candidates = windowCandidates()
        let windowAssignments = AppKeyAssignmentStore.shared.windowAssignments(
            for: character,
            in: assignment
        )
        guard !windowAssignments.isEmpty else {
            debug("no scoped window assignment for \(assignment.appName) + \(character)")
            resetCycleState()
            return true
        }

        return switchToAssignedWindow(
            windowAssignments, candidates: candidates, character: character,
            beepOnUnavailable: false)
    }

    private func switchToAssignedWindow(
        _ assignments: [WindowKeyAssignment],
        candidates: [Candidate],
        character: Character,
        beepOnUnavailable: Bool = true
    ) -> Bool {
        let assignedWindowIDs = Set(assignments.map(\.windowID))
        let matches = candidates.filter { assignedWindowIDs.contains($0.windowID) }
        guard !matches.isEmpty else {
            debug("window assignment exists for \(character), but assigned window is unavailable")
            for assignment in assignments {
                AppKeyAssignmentStore.shared.removeWindowAssignment(windowID: assignment.windowID)
            }
            if beepOnUnavailable {
                DispatchQueue.main.async { NSSound.beep() }
            }
            resetCycleState()
            return true
        }

        let candidate = candidateToFocus(from: matches, character: character)
        debug(
            "matched assigned windowID=\(candidate.windowID) app=\(candidate.ownerName) title=\(candidate.title)"
        )
        performWindowSpaceSwitchWithOverlay(candidate: candidate)
        return true
    }

    private func switchToAppAssignedWindow(
        _ assignments: [AppKeyAssignment], candidates: [Candidate], character: Character
    ) -> Bool {
        let assignedBundleIDs = Set(assignments.map(\.bundleIdentifier))
        let matches = candidates.filter { candidate in
            guard let bundleIdentifier = candidate.bundleIdentifier else { return false }
            return assignedBundleIDs.contains(bundleIdentifier)
        }

        guard !matches.isEmpty else {
            debug(
                "app assignment exists for \(character), but no assigned app has switchable window candidates"
            )
            resetCycleState()
            return activateAssignedAppFallback(assignments)
        }

        let candidate = candidateToFocus(from: matches, character: character)
        debug(
            "matched assigned app windowID=\(candidate.windowID) app=\(candidate.ownerName) title=\(candidate.title)"
        )
        performWindowSpaceSwitchWithOverlay(candidate: candidate)
        return true
    }

    private func activateAssignedAppFallback(_ assignments: [AppKeyAssignment]) -> Bool {
        for assignment in assignments {
            guard
                let app = NSRunningApplication.runningApplications(
                    withBundleIdentifier: assignment.bundleIdentifier
                ).first
            else {
                continue
            }

            debug("fallback activating assigned app \(assignment.appName)")
            showSwitchOverlay()
            DispatchQueue.main.async {
                app.activate(options: [.activateIgnoringOtherApps])
                OSDWindow.shared.show(message: assignment.appName)
            }
            return true
        }

        debug("manual assignment exists, but assigned app is not running")
        DispatchQueue.main.async { NSSound.beep() }
        return true
    }

    private func candidateMatches(_ candidate: Candidate, character: Character) -> Bool {
        if firstComparableCharacter(in: candidate.title) == character {
            return true
        }
        return firstComparableCharacter(in: candidate.ownerName) == character
    }

    private func firstComparableCharacter(in string: String) -> Character? {
        normalizedAppName(string).first { char in
            char.isLetter || char.isNumber
        }
    }

    private func normalizedAppName(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func focus(candidate: Candidate, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.activateApp(pid: candidate.ownerPID)
            self.raiseAXWindow(candidate: candidate)
        }
    }

    private func activateApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps]
        )
    }

    private func raiseAXWindow(candidate: Candidate) {
        let appElement = AXUIElementCreateApplication(candidate.ownerPID)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return
        }

        let matchingWindow =
            windows.first { window in
                axTitle(for: window) == candidate.title
            } ?? windows.first

        guard let matchingWindow else { return }
        AXUIElementPerformAction(matchingWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, matchingWindow)
    }

    private func debug(_ message: String) {
        guard debugEnabled else { return }
        print("[RightCommandWindowSwitcher] \(message)")
    }

    private func showSwitchOverlay() {
        Task { @MainActor in
            SwitchOverlayController.shared.flash()
        }
    }

    private func quitApplication() {
        Task { @MainActor in
            NSApp.terminate(nil)
        }
    }

    private func performWindowSpaceSwitchWithOverlay(candidate: Candidate) {
        Task { @MainActor in
            SwitchOverlayController.shared.performTransition(
                { iss_switch_to_window_space(candidate.windowID) }
            ) { [weak self] switched in
                guard switched else {
                    self?.debug("failed to switch to Space for windowID=\(candidate.windowID)")
                    NSSound.beep()
                    return
                }

                self?.debug("switched to Space for windowID=\(candidate.windowID)")
                self?.focus(candidate: candidate, after: 0.12)
                OSDWindow.shared.show(message: candidate.displayName)
            }
        }
    }

    private func axTitle(for window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success
        else {
            return ""
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
