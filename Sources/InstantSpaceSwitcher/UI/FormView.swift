import AppKit

final class FormView: NSView {
  private let gridView = NSGridView()
  private var didConfigureColumns = false
  private var rowByControl: [ObjectIdentifier: NSGridRow] = [:]

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = 12
    gridView.rowSpacing = 12
    addSubview(gridView)

    NSLayoutConstraint.activate([
      gridView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
      gridView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      gridView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      gridView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var hasRows: Bool {
    return gridView.numberOfRows > 0
  }

  func addRow(label: NSView?, control: NSView) {
    let labelView = label ?? NSView()
    let row = gridView.addRow(with: [labelView, control])
    configureColumnsIfNeeded()
    rowByControl[ObjectIdentifier(control)] = row
    row.cell(at: 0).xPlacement = .trailing
    row.cell(at: 1).xPlacement = .fill
    row.cell(at: 0).yPlacement = .center
    row.cell(at: 1).yPlacement = .center
    control.setContentHuggingPriority(.defaultLow, for: .horizontal)
  }

  func setRowHidden(for control: NSView, hidden: Bool) {
    control.isHidden = hidden
    rowByControl[ObjectIdentifier(control)]?.isHidden = hidden
  }

  func addSectionHeading(_ title: String, control: NSView) {
    let label = NSTextField(labelWithString: title)
    addRow(label: label, control: control)
  }

  func addSectionSpacing() {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
    _ = gridView.addRow(with: [spacer, NSView()])
    configureColumnsIfNeeded()
  }

  func addVerticalFiller() {
    let filler = NSView()
    filler.setContentHuggingPriority(.defaultLow, for: .vertical)
    _ = gridView.addRow(with: [filler, NSView()])
    configureColumnsIfNeeded()
  }

  private func configureColumnsIfNeeded() {
    guard !didConfigureColumns, gridView.numberOfColumns >= 2 else { return }
    didConfigureColumns = true
    gridView.column(at: 0).width = 148
    gridView.column(at: 0).xPlacement = .trailing
    gridView.column(at: 1).xPlacement = .fill
  }
}
