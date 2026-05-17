//
//  DevicePickerWindowController.swift
//  Desk Controller
//
//  Programmatic window for picking a specific Bluetooth peripheral instead
//  of relying on the "name contains 'desk'" auto-discovery heuristic.
//

import Cocoa

@MainActor
final class DevicePickerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = DevicePickerWindowController()

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var devices: [DiscoveredDevice] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Choose Bluetooth Device"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        AppDelegate.bringToFront(window: self.window!)

        BluetoothManager.shared.onAvailableDevicesChange = { [weak self] devices in
            guard let self else { return }
            self.devices = devices
            self.tableView.reloadData()
            self.statusLabel.stringValue = "Found \(devices.count) device\(devices.count == 1 ? "" : "s")…"
        }
        BluetoothManager.shared.startScanningForSelection()
        statusLabel.stringValue = "Scanning…"
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        window?.delegate = self

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Device"
        nameColumn.width = 260

        let rssiColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rssi"))
        rssiColumn.title = "Signal"
        rssiColumn.width = 60

        let uuidColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("uuid"))
        uuidColumn.title = "UUID"
        uuidColumn.width = 120

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(rssiColumn)
        tableView.addTableColumn(uuidColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(connectSelected)
        scroll.documentView = tableView

        let connectButton = NSButton(title: "Connect to Selected", target: self, action: #selector(connectSelected))
        let clearButton = NSButton(title: "Use Auto-Discovery", target: self, action: #selector(clearSelection))
        let rescanButton = NSButton(title: "Rescan", target: self, action: #selector(rescan))

        let buttonRow = NSStackView(views: [rescanButton, NSView(), clearButton, connectButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let outer = NSStackView(views: [statusLabel, scroll, buttonRow])
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
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    @objc private func connectSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < devices.count else { return }
        BluetoothManager.shared.connectToDevice(uuid: devices[row].identifier.uuidString)
        close()
    }

    @objc private func clearSelection() {
        BluetoothManager.shared.clearDeviceSelection()
        BluetoothManager.shared.startScanning()
        close()
    }

    @objc private func rescan() {
        BluetoothManager.shared.startScanningForSelection()
        statusLabel.stringValue = "Rescanning…"
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { devices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < devices.count else { return nil }
        let device = devices[row]
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        switch column.identifier.rawValue {
        case "name":
            text.stringValue = device.name
        case "rssi":
            text.stringValue = "\(device.rssi) dBm"
        case "uuid":
            text.stringValue = String(device.identifier.uuidString.prefix(8)) + "…"
            text.textColor = .secondaryLabelColor
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

extension DevicePickerWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            BluetoothManager.shared.stopScanningForSelection()
        }
    }
}
