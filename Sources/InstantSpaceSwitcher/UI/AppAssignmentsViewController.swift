import AppKit
import Carbon
import Combine
import ISS

private final class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

final class AppAssignmentsViewController: NSViewController {
    private enum AssignmentKind: String {
        case app = "App"
        case window = "Window"
    }

    private struct ManualAssignmentRow {
        let kind: AssignmentKind
        let target: String
        let key: String
        let appAssignment: AppKeyAssignment?
        let windowAssignment: WindowKeyAssignment?
    }

    private struct ActiveTargetRow {
        let kind: AssignmentKind
        let target: String
        let bundleIdentifier: String?
        let appName: String
        let icon: NSImage?
        let windowID: UInt32?
        let windowTitle: String?
        let isIndented: Bool
        let isAssignable: Bool
    }

    private enum TableID {
        static let assigned = NSUserInterfaceItemIdentifier("assignedApps")
        static let active = NSUserInterfaceItemIdentifier("activeApps")
        static let target = NSUserInterfaceItemIdentifier("target")
        static let type = NSUserInterfaceItemIdentifier("type")
        static let key = NSUserInterfaceItemIdentifier("key")
        static let actions = NSUserInterfaceItemIdentifier("actions")
    }

    private let store = AppKeyAssignmentStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var assignedRows: [ManualAssignmentRow] = []
    private var activeRows: [ActiveTargetRow] = []
    private var recordingTarget: ActiveTargetRow?
    private var recordingExistingAssignment: ManualAssignmentRow?

    private let assignedLabel = NSTextField(labelWithString: "Manual Key Assignments")
    private let assignedTableView = NSTableView()
    private let assignedScrollView = NSScrollView()
    private let activeLabel = NSTextField(labelWithString: "Active Apps and Windows")
    private let activeTableView = NSTableView()
    private let activeScrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    override func loadView() {
        let captureView = KeyCaptureView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        captureView.onKeyDown = { [weak self] event in
            self?.handleCapturedKey(event)
        }
        view = captureView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindStore()
        reloadData()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
        reloadData()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopRecording()
    }

    deinit {
        GlobalEventTapRecorder.shared.stopRecording()
    }

    private func setupUI() {
        assignedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        activeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)

        setupAssignedTable()
        setupActiveTable()

        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        refreshButton.bezelStyle = .rounded

        for subview in [
            assignedLabel, assignedScrollView, activeLabel, activeScrollView, statusLabel,
            refreshButton,
        ] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            assignedLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            assignedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            refreshButton.centerYAnchor.constraint(equalTo: assignedLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            assignedScrollView.topAnchor.constraint(
                equalTo: assignedLabel.bottomAnchor, constant: 8),
            assignedScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            assignedScrollView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20),
            assignedScrollView.heightAnchor.constraint(equalToConstant: 165),

            activeLabel.topAnchor.constraint(
                equalTo: assignedScrollView.bottomAnchor, constant: 18),
            activeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            activeScrollView.topAnchor.constraint(equalTo: activeLabel.bottomAnchor, constant: 8),
            activeScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            activeScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            activeScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
    }

    private func setupAssignedTable() {
        assignedTableView.identifier = TableID.assigned
        assignedTableView.delegate = self
        assignedTableView.dataSource = self
        assignedTableView.rowHeight = 30
        assignedTableView.usesAlternatingRowBackgroundColors = true
        assignedTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let targetColumn = NSTableColumn(identifier: TableID.target)
        targetColumn.title = "Target"
        targetColumn.width = 300
        assignedTableView.addTableColumn(targetColumn)

        let typeColumn = NSTableColumn(identifier: TableID.type)
        typeColumn.title = "Type"
        typeColumn.width = 75
        assignedTableView.addTableColumn(typeColumn)

        let keyColumn = NSTableColumn(identifier: TableID.key)
        keyColumn.title = "Key"
        keyColumn.width = 55
        assignedTableView.addTableColumn(keyColumn)

        let actionsColumn = NSTableColumn(identifier: TableID.actions)
        actionsColumn.title = "Actions"
        actionsColumn.width = 160
        assignedTableView.addTableColumn(actionsColumn)

        assignedScrollView.documentView = assignedTableView
        assignedScrollView.hasVerticalScroller = true
        assignedScrollView.borderType = .bezelBorder
    }

    private func setupActiveTable() {
        activeTableView.identifier = TableID.active
        activeTableView.delegate = self
        activeTableView.dataSource = self
        activeTableView.rowHeight = 30
        activeTableView.usesAlternatingRowBackgroundColors = true
        activeTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let targetColumn = NSTableColumn(identifier: TableID.target)
        targetColumn.title = "Target"
        targetColumn.width = 380
        activeTableView.addTableColumn(targetColumn)

        let typeColumn = NSTableColumn(identifier: TableID.type)
        typeColumn.title = "Type"
        typeColumn.width = 75
        activeTableView.addTableColumn(typeColumn)

        let actionsColumn = NSTableColumn(identifier: TableID.actions)
        actionsColumn.title = "Actions"
        actionsColumn.width = 140
        activeTableView.addTableColumn(actionsColumn)

        activeScrollView.documentView = activeTableView
        activeScrollView.hasVerticalScroller = true
        activeScrollView.borderType = .bezelBorder
    }

    private func bindStore() {
        store.$assignments.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reloadData()
        }.store(in: &cancellables)

        store.$windowAssignments.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.reloadData()
        }.store(in: &cancellables)
    }

    private func reloadData() {
        assignedRows =
            store.assignments.map {
                ManualAssignmentRow(
                    kind: .app,
                    target: $0.appName,
                    key: $0.key,
                    appAssignment: $0,
                    windowAssignment: nil
                )
            }
            + store.windowAssignments.map {
                ManualAssignmentRow(
                    kind: .window,
                    target: $0.targetName,
                    key: $0.key,
                    appAssignment: nil,
                    windowAssignment: $0
                )
            }
        assignedRows.sort {
            $0.target.localizedCaseInsensitiveCompare($1.target) == .orderedAscending
        }
        activeRows = activeTargets()
        assignedTableView.reloadData()
        activeTableView.reloadData()
    }

    private func activeTargets() -> [ActiveTargetRow] {
        let windows = switchableWindows()
        let grouped = Dictionary(
            grouping: windows, by: { $0.bundleIdentifier ?? "pid:\($0.ownerPID)" })
        let sortedGroups = grouped.values.sorted { lhs, rhs in
            (lhs.first?.appName ?? "").localizedCaseInsensitiveCompare(rhs.first?.appName ?? "")
                == .orderedAscending
        }

        var rows: [ActiveTargetRow] = []
        for group in sortedGroups {
            guard let first = group.first else { continue }
            let appIsAssigned =
                first.bundleIdentifier.map { store.isAssigned(bundleIdentifier: $0) } ?? false
            rows.append(
                ActiveTargetRow(
                    kind: .app,
                    target: first.appName,
                    bundleIdentifier: first.bundleIdentifier,
                    appName: first.appName,
                    icon: first.icon,
                    windowID: nil,
                    windowTitle: nil,
                    isIndented: false,
                    isAssignable: first.bundleIdentifier != nil && !appIsAssigned
                )
            )

            let sortedWindows = group.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
                    == .orderedAscending
            }
            for window in sortedWindows {
                let windowIsAssigned = store.windowAssignments.contains {
                    $0.windowID == window.windowID
                }
                rows.append(
                    ActiveTargetRow(
                        kind: .window,
                        target: window.displayTitle,
                        bundleIdentifier: window.bundleIdentifier,
                        appName: window.appName,
                        icon: window.icon,
                        windowID: window.windowID,
                        windowTitle: window.windowTitle,
                        isIndented: true,
                        isAssignable: !windowIsAssigned
                    )
                )
            }
        }
        return rows
    }

    private struct SwitchableWindow {
        let windowID: UInt32
        let ownerPID: pid_t
        let bundleIdentifier: String?
        let appName: String
        let windowTitle: String
        let icon: NSImage?

        var displayTitle: String {
            if windowTitle.isEmpty {
                return "Untitled Window #\(windowID)"
            }
            return windowTitle
        }
    }

    private func switchableWindows() -> [SwitchableWindow] {
        guard
            let infoList = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        var seenWindowIDs = Set<UInt32>()
        var windows: [SwitchableWindow] = []

        for info in infoList {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else {
                continue
            }

            let pid = pid_t(pidNumber.int32Value)
            guard pid != currentPID, !seenWindowIDs.contains(windowNumber) else { continue }

            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 {
                continue
            }

            if let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width <= 1 || bounds.height <= 1
            {
                continue
            }

            var spaceInfo = ISSWindowSpaceInfo()
            guard iss_get_window_space_info(windowNumber, &spaceInfo) else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            let appName =
                (info[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                ?? app?.localizedName
                ?? "Unknown App"
            let title =
                (info[kCGWindowName as String] as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""

            seenWindowIDs.insert(windowNumber)
            windows.append(
                SwitchableWindow(
                    windowID: windowNumber,
                    ownerPID: pid,
                    bundleIdentifier: app?.bundleIdentifier,
                    appName: appName,
                    windowTitle: title,
                    icon: app?.icon
                )
            )
        }

        return windows
    }

    @objc private func refreshClicked() {
        reloadData()
        setStatus("Refreshed active apps and windows.")
    }

    @objc private func assignActiveTarget(_ sender: NSButton) {
        guard sender.tag < activeRows.count else { return }
        beginRecording(for: activeRows[sender.tag], existingAssignment: nil)
    }

    @objc private func changeAssignedTarget(_ sender: NSButton) {
        guard sender.tag < assignedRows.count else { return }
        let row = assignedRows[sender.tag]
        let target: ActiveTargetRow
        if let appAssignment = row.appAssignment {
            target = ActiveTargetRow(
                kind: .app,
                target: appAssignment.appName,
                bundleIdentifier: appAssignment.bundleIdentifier,
                appName: appAssignment.appName,
                icon: NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: appAssignment.bundleIdentifier
                )
                .map { NSWorkspace.shared.icon(forFile: $0.path) },
                windowID: nil,
                windowTitle: nil,
                isIndented: false,
                isAssignable: true
            )
        } else if let windowAssignment = row.windowAssignment {
            target = ActiveTargetRow(
                kind: .window,
                target: windowAssignment.targetName,
                bundleIdentifier: windowAssignment.bundleIdentifier,
                appName: windowAssignment.appName,
                icon: windowAssignment.bundleIdentifier.flatMap {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
                }
                .map { NSWorkspace.shared.icon(forFile: $0.path) },
                windowID: windowAssignment.windowID,
                windowTitle: windowAssignment.windowTitle,
                isIndented: true,
                isAssignable: true
            )
        } else {
            return
        }
        beginRecording(for: target, existingAssignment: row)
    }

    @objc private func removeAssignedTarget(_ sender: NSButton) {
        guard sender.tag < assignedRows.count else { return }
        let row = assignedRows[sender.tag]
        if let appAssignment = row.appAssignment {
            store.removeAssignment(bundleIdentifier: appAssignment.bundleIdentifier)
        } else if let windowAssignment = row.windowAssignment {
            store.removeWindowAssignment(windowID: windowAssignment.windowID)
        }
        setStatus("Removed assignment for \(row.target).")
    }

    private func beginRecording(
        for target: ActiveTargetRow, existingAssignment: ManualAssignmentRow?
    ) {
        stopRecording()
        recordingTarget = target
        recordingExistingAssignment = existingAssignment
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(view)
        GlobalEventTapRecorder.shared.startRecording(
            onKeyPress: { [weak self] event in
                self?.handleCapturedKey(event)
            },
            onMouseClick: { [weak self] in
                self?.stopRecording()
                self?.setStatus("Cancelled assignment.")
            }
        )
        setStatus("Press a letter or number for \(target.target). Press Esc to cancel.")
    }

    private func stopRecording() {
        GlobalEventTapRecorder.shared.stopRecording()
        recordingTarget = nil
        recordingExistingAssignment = nil
    }

    private func handleCapturedKey(_ event: NSEvent) {
        guard let target = recordingTarget else { return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            setStatus("Cancelled assignment.")
            return
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased().first,
            key.isLetter || key.isNumber
        else {
            NSSound.beep()
            setStatus("Use a single letter or number.")
            return
        }

        switch target.kind {
        case .app:
            guard let bundleIdentifier = target.bundleIdentifier else {
                NSSound.beep()
                setStatus("Cannot assign app without a bundle identifier.")
                stopRecording()
                return
            }
            store.setAssignment(
                bundleIdentifier: bundleIdentifier, appName: target.appName, key: key)
        case .window:
            guard let windowID = target.windowID else {
                NSSound.beep()
                setStatus("Cannot assign window without a window ID.")
                stopRecording()
                return
            }
            store.setWindowAssignment(
                windowID: windowID,
                bundleIdentifier: target.bundleIdentifier,
                appName: target.appName,
                windowTitle: target.windowTitle ?? "",
                key: key
            )
            Task { @MainActor in
                SwitchOverlayController.shared.flash()
            }
        }

        stopRecording()
        setStatus("Assigned Right Command + \(String(key).uppercased()) to \(target.target).")
    }

    private func setStatus(_ message: String) {
        statusLabel.stringValue = message
    }
}

extension AppAssignmentsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView.identifier == TableID.assigned ? assignedRows.count : activeRows.count
    }
}

extension AppAssignmentsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        if tableView.identifier == TableID.assigned {
            return assignedCell(tableColumn: tableColumn, row: row)
        }
        return activeCell(tableColumn: tableColumn, row: row)
    }

    private func assignedCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let assignment = assignedRows[row]
        switch tableColumn?.identifier {
        case TableID.target:
            return targetCell(
                name: assignment.target, icon: icon(for: assignment), isIndented: false)
        case TableID.type:
            return paddedCell(NSTextField(labelWithString: assignment.kind.rawValue))
        case TableID.key:
            let text = NSTextField(labelWithString: assignment.key.uppercased())
            text.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            return paddedCell(text)
        case TableID.actions:
            let container = NSStackView()
            container.orientation = .horizontal
            container.spacing = 8
            container.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)

            let change = NSButton(
                title: "Change…", target: self, action: #selector(changeAssignedTarget(_:)))
            change.tag = row
            change.bezelStyle = .rounded
            change.controlSize = .small
            let remove = NSButton(
                title: "Remove", target: self, action: #selector(removeAssignedTarget(_:)))
            remove.tag = row
            remove.bezelStyle = .rounded
            remove.controlSize = .small
            container.addArrangedSubview(change)
            container.addArrangedSubview(remove)
            return container
        default:
            return nil
        }
    }

    private func activeCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let target = activeRows[row]
        switch tableColumn?.identifier {
        case TableID.target:
            return targetCell(
                name: target.target, icon: target.isIndented ? nil : target.icon,
                isIndented: target.isIndented)
        case TableID.type:
            return paddedCell(NSTextField(labelWithString: target.kind.rawValue))
        case TableID.actions:
            let title: String
            if !target.isAssignable {
                title = target.kind == .app ? "Assigned" : "Assigned"
            } else {
                title = target.kind == .app ? "Assign App…" : "Assign Window…"
            }
            let button = NSButton(
                title: title, target: self, action: #selector(assignActiveTarget(_:)))
            button.tag = row
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.isEnabled = target.isAssignable
            return paddedCell(button)
        default:
            return nil
        }
    }

    private func icon(for assignment: ManualAssignmentRow) -> NSImage? {
        let bundleIdentifier =
            assignment.appAssignment?.bundleIdentifier
            ?? assignment.windowAssignment?.bundleIdentifier
        return
            bundleIdentifier
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func targetCell(name: String, icon: NSImage?, isIndented: Bool) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: isIndented ? 24 : 4, bottom: 4, right: 4)

        if let icon {
            let imageView = NSImageView(image: icon)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
            ])
            stack.addArrangedSubview(imageView)
        }

        let label = NSTextField(labelWithString: name)
        if isIndented {
            label.textColor = .secondaryLabelColor
        }
        stack.addArrangedSubview(label)
        return stack
    }

    private func paddedCell(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}
