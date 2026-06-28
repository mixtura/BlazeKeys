import AppKit

private struct OverlayEffectParameter {
    let label: String
    let key: String
    let range: ClosedRange<Double>
}

private final class OverlayEffectParameterSlider: NSSlider {
    let parameterKey: String

    init(parameterKey: String, range: ClosedRange<Double>) {
        self.parameterKey = parameterKey
        super.init(frame: .zero)
        minValue = range.lowerBound
        maxValue = range.upperBound
        isContinuous = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class SwitchOverlayPreferencesView: NSObject {
    let stylePopup = NSPopUpButton()
    let settingsPanel = NSStackView()
    var onSettingsVisibilityChanged: ((Bool) -> Void)?

    private let edgeGlowSettingsContainer = NSStackView()
    private let primaryColorWell = NSColorWell()
    private let accentColorWell = NSColorWell()
    private let resetEdgeGlowButton = NSButton(title: "Reset Edge Glow", target: nil, action: nil)
    private let animateEdgeThicknessCheckbox = NSButton(
        checkboxWithTitle: "Animate edge thickness", target: nil, action: nil)
    private let animateEdgeFadeCheckbox = NSButton(
        checkboxWithTitle: "Animate edge fade", target: nil, action: nil)
    private var edgeGlowSliders: [OverlayEffectParameterSlider] = []
    private var edgeGlowValueLabels: [String: NSTextField] = [:]

    private let edgeGlowParameters: [OverlayEffectParameter] = [
        OverlayEffectParameter(
            label: "Duration", key: EdgeGlowSettings.durationKey, range: 0.12...1.00),
        OverlayEffectParameter(
            label: "Intro Duration", key: EdgeGlowSettings.fadeInDurationKey, range: 0.02...0.40),
        OverlayEffectParameter(
            label: "Outro Start", key: EdgeGlowSettings.fadeOutStartKey, range: 0.04...0.80),
        OverlayEffectParameter(
            label: "Outro End", key: EdgeGlowSettings.fadeOutEndKey, range: 0.08...1.00),
        OverlayEffectParameter(
            label: "Edge Thickness", key: EdgeGlowSettings.thicknessKey, range: 0.5...24.0),
        OverlayEffectParameter(
            label: "Glow Width", key: EdgeGlowSettings.glowWidthKey, range: 10.0...180.0),
        OverlayEffectParameter(
            label: "Wave Density", key: EdgeGlowSettings.waveDensityKey, range: 0.0...140.0),
        OverlayEffectParameter(
            label: "Wave Speed", key: EdgeGlowSettings.waveSpeedKey, range: 0.0...120.0),
    ]
    private let edgeGlowDurationKey = EdgeGlowSettings.durationKey
    private let edgeGlowTimingParameterKeys: Set<String> = [
        EdgeGlowSettings.fadeInDurationKey,
        EdgeGlowSettings.fadeOutStartKey,
        EdgeGlowSettings.fadeOutEndKey,
    ]

    override init() {
        super.init()
        setupView()
        loadSettings()
    }

    private func setupView() {
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)
        for style in SwitchOverlayStyle.allCases {
            stylePopup.addItem(withTitle: style.displayName)
        }

        setupEdgeGlowSettingsContainer()

        settingsPanel.orientation = .vertical
        settingsPanel.alignment = .leading
        settingsPanel.spacing = 12
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.addArrangedSubview(edgeGlowSettingsContainer)
    }

    private func setupEdgeGlowSettingsContainer() {
        edgeGlowSettingsContainer.orientation = .vertical
        edgeGlowSettingsContainer.alignment = .leading
        edgeGlowSettingsContainer.spacing = 12
        edgeGlowSettingsContainer.translatesAutoresizingMaskIntoConstraints = false
        edgeGlowSettingsContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        primaryColorWell.target = self
        primaryColorWell.action = #selector(primaryColorChanged)
        accentColorWell.target = self
        accentColorWell.action = #selector(accentColorChanged)
        resetEdgeGlowButton.target = self
        resetEdgeGlowButton.action = #selector(resetEdgeGlowSettings)
        animateEdgeThicknessCheckbox.target = self
        animateEdgeThicknessCheckbox.action = #selector(animateEdgeThicknessChanged)
        animateEdgeFadeCheckbox.target = self
        animateEdgeFadeCheckbox.action = #selector(animateEdgeFadeChanged)

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 14
        colorRow.alignment = .centerY
        colorRow.addArrangedSubview(colorWellGroup(title: "Primary", colorWell: primaryColorWell))
        colorRow.addArrangedSubview(colorWellGroup(title: "Accent", colorWell: accentColorWell))
        edgeGlowSettingsContainer.addArrangedSubview(colorRow)
        edgeGlowSettingsContainer.addArrangedSubview(resetEdgeGlowButton)

        for parameter in edgeGlowParameters where parameter.key == edgeGlowDurationKey {
            addEdgeGlowSliderRow(parameter)
        }

        let animationOptionsRow = NSStackView()
        animationOptionsRow.orientation = .horizontal
        animationOptionsRow.spacing = 16
        animationOptionsRow.alignment = .centerY
        animationOptionsRow.addArrangedSubview(animateEdgeThicknessCheckbox)
        animationOptionsRow.addArrangedSubview(animateEdgeFadeCheckbox)
        edgeGlowSettingsContainer.addArrangedSubview(animationOptionsRow)

        for parameter in edgeGlowParameters where edgeGlowTimingParameterKeys.contains(parameter.key) {
            addOverlaySliderRow(
                parameter,
                sliders: &edgeGlowSliders,
                valueLabels: &edgeGlowValueLabels,
                action: #selector(edgeGlowSliderChanged),
                container: edgeGlowSettingsContainer
            )
        }

        for parameter in edgeGlowParameters
        where parameter.key != edgeGlowDurationKey
            && !edgeGlowTimingParameterKeys.contains(parameter.key)
        {
            addOverlaySliderRow(
                parameter,
                sliders: &edgeGlowSliders,
                valueLabels: &edgeGlowValueLabels,
                action: #selector(edgeGlowSliderChanged),
                container: edgeGlowSettingsContainer
            )
        }
    }

    private func loadSettings() {
        let currentStyle = SwitchOverlayStyle.current
        if let index = SwitchOverlayStyle.allCases.firstIndex(of: currentStyle) {
            stylePopup.selectItem(at: index)
        } else {
            stylePopup.selectItem(at: 0)
        }

        primaryColorWell.color = EdgeGlowColorSettings.primaryColor
        accentColorWell.color = EdgeGlowColorSettings.accentColor
        animateEdgeThicknessCheckbox.state = EdgeGlowSettings.animateThickness ? .on : .off
        animateEdgeFadeCheckbox.state = EdgeGlowSettings.animateFade ? .on : .off
        reloadEdgeGlowControls()
        updateEdgeGlowSettingsVisibility()
        updateEdgeGlowTimingControlsEnabledState()
    }

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < SwitchOverlayStyle.allCases.count else { return }

        let style = SwitchOverlayStyle.allCases[index]
        SwitchOverlayController.shared.setStyle(style)
        updateEdgeGlowSettingsVisibility()

        guard style != .none else { return }

        if style == .snapshotReveal {
            if !ScreenSnapshotCapture.ensureAccess(requestIfNeeded: true) {
                presentSnapshotRevealPermissionAlert()
            }
            SwitchOverlayController.shared.flashSnapshotPreview()
        } else {
            SwitchOverlayController.shared.flash()
        }
    }

    @objc private func primaryColorChanged(_ sender: NSColorWell) {
        EdgeGlowColorSettings.primaryColor = sender.color
        SwitchOverlayController.shared.flash()
    }

    @objc private func accentColorChanged(_ sender: NSColorWell) {
        EdgeGlowColorSettings.accentColor = sender.color
        SwitchOverlayController.shared.flash()
    }

    @objc private func edgeGlowSliderChanged(_ sender: OverlayEffectParameterSlider) {
        EdgeGlowSettings.set(Float(sender.doubleValue), for: sender.parameterKey)
        sender.doubleValue = Double(EdgeGlowSettings.value(sender.parameterKey))
        updateEdgeGlowValueLabel(for: sender.parameterKey)
        SwitchOverlayController.shared.flash()
    }

    @objc private func animateEdgeThicknessChanged(_ sender: NSButton) {
        EdgeGlowSettings.animateThickness = sender.state == .on
        updateEdgeGlowTimingControlsEnabledState()
        SwitchOverlayController.shared.flash()
    }

    @objc private func animateEdgeFadeChanged(_ sender: NSButton) {
        EdgeGlowSettings.animateFade = sender.state == .on
        updateEdgeGlowTimingControlsEnabledState()
        SwitchOverlayController.shared.flash()
    }

    @objc private func resetEdgeGlowSettings(_ sender: NSButton) {
        EdgeGlowSettings.resetToDefaults()
        EdgeGlowColorSettings.resetToDefaults()
        primaryColorWell.color = EdgeGlowColorSettings.primaryColor
        accentColorWell.color = EdgeGlowColorSettings.accentColor
        animateEdgeThicknessCheckbox.state = EdgeGlowSettings.animateThickness ? .on : .off
        animateEdgeFadeCheckbox.state = EdgeGlowSettings.animateFade ? .on : .off
        reloadEdgeGlowControls()
        updateEdgeGlowTimingControlsEnabledState()
        SwitchOverlayController.shared.flash()
    }

    private func updateEdgeGlowSettingsVisibility() {
        let showsEdgeGlow = SwitchOverlayStyle.current == .edgeGlow
        onSettingsVisibilityChanged?(showsEdgeGlow)
    }

    private func updateEdgeGlowTimingControlsEnabledState() {
        let animateThickness = animateEdgeThicknessCheckbox.state == .on
        let animateFade = animateEdgeFadeCheckbox.state == .on
        let timingEnabled = animateThickness || animateFade

        for slider in edgeGlowSliders where edgeGlowTimingParameterKeys.contains(slider.parameterKey) {
            slider.isEnabled = timingEnabled
        }
        for key in edgeGlowTimingParameterKeys {
            edgeGlowValueLabels[key]?.textColor =
                timingEnabled ? .secondaryLabelColor : .disabledControlTextColor
        }
    }

    private func addEdgeGlowSliderRow(_ parameter: OverlayEffectParameter) {
        addOverlaySliderRow(
            parameter,
            sliders: &edgeGlowSliders,
            valueLabels: &edgeGlowValueLabels,
            action: #selector(edgeGlowSliderChanged),
            container: edgeGlowSettingsContainer
        )
    }

    private func addOverlaySliderRow(
        _ parameter: OverlayEffectParameter,
        sliders: inout [OverlayEffectParameterSlider],
        valueLabels: inout [String: NSTextField],
        action: Selector,
        container: NSStackView
    ) {
        let slider = OverlayEffectParameterSlider(parameterKey: parameter.key, range: parameter.range)
        slider.target = self
        slider.action = action
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        sliders.append(slider)

        let nameLabel = NSTextField(labelWithString: parameter.label + ":")
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        nameLabel.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        valueLabels[parameter.key] = valueLabel

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        container.addArrangedSubview(row)
    }

    private func colorWellGroup(title: String, colorWell: NSColorWell) -> NSView {
        let group = NSStackView()
        group.orientation = .horizontal
        group.spacing = 6
        group.alignment = .centerY
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        group.addArrangedSubview(NSTextField(labelWithString: title + ":"))
        group.addArrangedSubview(colorWell)
        return group
    }

    private func reloadEdgeGlowControls() {
        for slider in edgeGlowSliders {
            slider.doubleValue = Double(EdgeGlowSettings.value(slider.parameterKey))
            updateEdgeGlowValueLabel(for: slider.parameterKey)
        }
    }

    private func updateEdgeGlowValueLabel(for key: String) {
        edgeGlowValueLabels[key]?.stringValue = formattedOverlayValue(EdgeGlowSettings.value(key))
    }

    private func formattedOverlayValue(_ value: Float) -> String {
        if value < 1 {
            return String(format: "%.3f", value)
        }
        if value < 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.1f", value)
    }

    private func presentSnapshotRevealPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText =
            "Snapshot Reveal needs Screen Recording access to capture windows and apps, not just the wallpaper. Enable InstantSpaceSwitcher in System Settings > Privacy & Security > Screen Recording, then try again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
