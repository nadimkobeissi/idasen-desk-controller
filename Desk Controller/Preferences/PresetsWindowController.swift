//
//  PresetsWindowController.swift
//  Desk Controller
//
//  Programmatic window for managing custom desk-height presets.
//

import Cocoa

@MainActor
final class PresetsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = PresetsWindowController()

    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let heightField = NSTextField()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Manage Presets"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presetsChanged),
            name: .presetsDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppDelegate.bringToFront(window: self.window!)
        tableView.reloadData()
    }

    @objc private func presetsChanged() { tableView.reloadData() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 200

        let unit = Preferences.shared.isMetric ? "cm" : "in"
        let heightColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("height"))
        heightColumn.title = "Height (\(unit))"
        heightColumn.width = 100

        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "Type"
        typeColumn.width = 80

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(heightColumn)
        tableView.addTableColumn(typeColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        scroll.documentView = tableView

        let addNameLabel = NSTextField(labelWithString: "Name:")
        nameField.placeholderString = "e.g. Standing tall"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.target = self
        nameField.action = #selector(addPreset)

        let addHeightLabel = NSTextField(labelWithString: "Height:")
        heightField.placeholderString = unit
        heightField.translatesAutoresizingMaskIntoConstraints = false
        heightField.target = self
        heightField.action = #selector(addPreset)

        let addButton = NSButton(title: "Add", target: self, action: #selector(addPreset))
        let deleteButton = NSButton(title: "Delete Selected", target: self, action: #selector(deleteSelected))
        let formStack = NSStackView(views: [addNameLabel, nameField, addHeightLabel, heightField, addButton])
        formStack.orientation = .horizontal
        formStack.spacing = 8
        formStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [deleteButton, NSView()])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let outer = NSStackView(views: [scroll, formStack, buttonRow])
        outer.orientation = .vertical
        outer.spacing = 10
        outer.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        outer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            outer.topAnchor.constraint(equalTo: content.topAnchor),
            outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            heightField.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    @objc private func addPreset() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var value = Float(heightField.stringValue) else { return }
        if !Preferences.shared.isMetric { value = value.convertToCentimeters() }
        PresetManager.shared.addPreset(name: name, heightCm: value)
        nameField.stringValue = ""
        heightField.stringValue = ""
    }

    @objc private func deleteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < PresetManager.shared.presets.count else { return }
        let preset = PresetManager.shared.presets[row]
        guard !preset.isBuiltIn else { return }
        PresetManager.shared.deletePreset(id: preset.id)
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { PresetManager.shared.presets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let preset = PresetManager.shared.presets[row]
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail

        switch column.identifier.rawValue {
        case "name":
            text.stringValue = preset.name
        case "height":
            let display = Preferences.shared.isMetric ? preset.heightCm : preset.heightCm.convertToInches()
            text.stringValue = String(format: "%.1f", display)
        case "type":
            text.stringValue = preset.isBuiltIn ? "Built-in" : "Custom"
            text.textColor = preset.isBuiltIn ? .secondaryLabelColor : .labelColor
        default:
            text.stringValue = ""
        }

        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
