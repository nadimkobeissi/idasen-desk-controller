//
//  PreferencesWindowController.swift
//  Desk Controller
//
//  Created by David Williames on 11/1/21.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    @IBOutlet weak var standingHeightField: NSTextField!
    @IBOutlet weak var sittingHeightField: NSTextField!

    @IBOutlet weak var unitsPopUpButton: NSPopUpButton!
    @IBOutlet weak var currentHeightField: NSTextField?

    @IBOutlet weak var autoStandEnabledCheckbox: NSButton!
    @IBOutlet weak var autoStandIntervalStepper: NSStepper!
    @IBOutlet weak var autoStandIntervalLabel: NSTextField!
    @IBOutlet weak var autoStandInactiveStepper: NSStepper!
    @IBOutlet weak var autoStandInactiveLabel: NSTextField!

    @IBOutlet weak var openAtLoginCheckbox: NSButton!

    // Device selection UI (created programmatically)
    private var connectedDeviceLabel: NSTextField!
    private var devicePopUpButton: NSPopUpButton!
    private var refreshButton: NSButton!
    private var clearSelectionButton: NSButton!

    private var discoveredDevices: [DiscoveredDevice] = []

    static let sharedInstance = PreferencesWindowController(windowNibName: "PreferencesWindowController")

    var deskController: DeskController? {
        didSet {
            deskPosition = deskController?.desk.position
        }
    }

    var deskPosition: Float? {
        didSet {
            currentHeightField?.isEnabled = (deskPosition != nil)

            var offsetPosition = Preferences.shared.positionOffset + (deskPosition ?? 0)
            if !Preferences.shared.isMetric {
                offsetPosition = offsetPosition.convertToInches()
            }
            currentHeightField?.stringValue = String(format: "%.1f", offsetPosition)
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        window?.delegate = self

        openAtLoginCheckbox.state = Preferences.shared.openAtLogin ? .on : .off

        unitsPopUpButton.selectItem(at: Preferences.shared.isMetric ? 0 : 1)

        autoStandEnabledCheckbox.state = Preferences.shared.automaticStandEnabled ? .on : .off
        autoStandIntervalStepper.intValue = Int32(Preferences.shared.automaticStandPerHour / 60)
        autoStandInactiveStepper.intValue = Int32(Preferences.shared.automaticStandInactivity / 60)

        updateLabels()

        deskController?.onPositionChange({ [weak self] position in
            self?.deskPosition = position
        })

        // Setup device selection UI
        setupDeviceSelectionUI()

        // Subscribe to device discovery updates
        BluetoothManager.shared.onAvailablePeripheralsChange = { [weak self] devices in
            self?.discoveredDevices = devices
            self?.updateDeviceDropdown()
        }

        // Subscribe to connection state changes
        let previousCallback = BluetoothManager.shared.onConnectedPeripheralChange
        BluetoothManager.shared.onConnectedPeripheralChange = { [weak self] peripheral in
            previousCallback(peripheral)
            DispatchQueue.main.async {
                self?.updateConnectedDeviceLabel()
                self?.updateDeviceDropdown()
            }
        }

        // Load current devices
        discoveredDevices = BluetoothManager.shared.availablePeripherals
        updateDeviceDropdown()
        updateConnectedDeviceLabel()
        updateClearButtonState()
    }

    private func setupDeviceSelectionUI() {
        guard let contentView = window?.contentView else { return }

        // Expand window height to accommodate device selection
        if var frame = window?.frame {
            frame.size.height += 90
            frame.origin.y -= 90
            window?.setFrame(frame, display: true)
        }

        // Shift existing content down
        for subview in contentView.subviews {
            var frame = subview.frame
            frame.origin.y -= 90
            subview.frame = frame
        }

        let windowWidth = contentView.frame.width

        // Section label
        let sectionLabel = NSTextField(labelWithString: "Bluetooth Device")
        sectionLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sectionLabel.frame = NSRect(x: 20, y: contentView.frame.height - 25, width: windowWidth - 40, height: 17)
        contentView.addSubview(sectionLabel)

        // Connected device label
        connectedDeviceLabel = NSTextField(labelWithString: "Not connected")
        connectedDeviceLabel.font = NSFont.systemFont(ofSize: 12)
        connectedDeviceLabel.textColor = .secondaryLabelColor
        connectedDeviceLabel.frame = NSRect(x: 20, y: contentView.frame.height - 45, width: windowWidth - 40, height: 17)
        contentView.addSubview(connectedDeviceLabel)

        // Device dropdown
        devicePopUpButton = NSPopUpButton(frame: NSRect(x: 20, y: contentView.frame.height - 72, width: windowWidth - 40, height: 25), pullsDown: false)
        devicePopUpButton.target = self
        devicePopUpButton.action = #selector(deviceSelected(_:))
        contentView.addSubview(devicePopUpButton)

        // Buttons row
        refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshButtonClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 20, y: contentView.frame.height - 100, width: 70, height: 22)
        contentView.addSubview(refreshButton)

        clearSelectionButton = NSButton(title: "Clear", target: self, action: #selector(clearSelectionButtonClicked))
        clearSelectionButton.bezelStyle = .rounded
        clearSelectionButton.frame = NSRect(x: 95, y: contentView.frame.height - 100, width: 60, height: 22)
        contentView.addSubview(clearSelectionButton)
    }

    private func updateDeviceDropdown() {
        devicePopUpButton.removeAllItems()

        // Check if we have a connected peripheral that should be shown
        let connectedPeripheral = BluetoothManager.shared.connectedPeripheral
        let savedUUID = Preferences.shared.selectedDeviceUUID

        // Build the list of devices to show
        var devicesToShow = discoveredDevices

        // If we have a connected device not in the list, add it (only if it has a name)
        if let connected = connectedPeripheral,
           let connectedName = connected.name,
           !connectedName.isEmpty,
           !devicesToShow.contains(where: { $0.identifier == connected.identifier }) {
            let connectedDevice = DiscoveredDevice(
                peripheral: connected,
                name: connectedName,
                rssi: 0,
                identifier: connected.identifier
            )
            devicesToShow.insert(connectedDevice, at: 0)
        }

        if devicesToShow.isEmpty {
            devicePopUpButton.addItem(withTitle: "Scanning for devices...")
            devicePopUpButton.isEnabled = false
        } else {
            devicePopUpButton.isEnabled = true

            // Add placeholder if no device is selected
            if savedUUID == nil {
                devicePopUpButton.addItem(withTitle: "Select a device...")
                devicePopUpButton.item(at: 0)?.isEnabled = false
            }

            // Add all devices
            for device in devicesToShow {
                devicePopUpButton.addItem(withTitle: device.name)

                // Store the UUID in the menu item's represented object
                if let menuItem = devicePopUpButton.lastItem {
                    menuItem.representedObject = device.identifier.uuidString
                }
            }

            // Select the saved device if it exists
            if let savedUUID = savedUUID {
                for i in 0..<devicePopUpButton.numberOfItems {
                    if let uuid = devicePopUpButton.item(at: i)?.representedObject as? String,
                       uuid == savedUUID {
                        devicePopUpButton.selectItem(at: i)
                        break
                    }
                }
            }
        }

        updateConnectedDeviceLabel()
        updateClearButtonState()
    }

    private func updateConnectedDeviceLabel() {
        // First check if we have an actual connected peripheral
        if let connectedPeripheral = BluetoothManager.shared.connectedPeripheral,
           connectedPeripheral.state == .connected {
            let name = connectedPeripheral.name ?? "Unknown Device"
            connectedDeviceLabel.stringValue = "Connected: \(name)"
            connectedDeviceLabel.textColor = NSColor.systemGreen
            return
        }

        // Check if we have a saved device we're trying to connect to
        if let savedUUID = Preferences.shared.selectedDeviceUUID {
            // Try to find the name from discovered devices or connected peripheral
            if let device = discoveredDevices.first(where: { $0.identifier.uuidString == savedUUID }) {
                connectedDeviceLabel.stringValue = "Connecting to: \(device.name)..."
                connectedDeviceLabel.textColor = NSColor.systemOrange
            } else if let connectedPeripheral = BluetoothManager.shared.connectedPeripheral,
                      connectedPeripheral.identifier.uuidString == savedUUID {
                let name = connectedPeripheral.name ?? "Unknown Device"
                connectedDeviceLabel.stringValue = "Connecting to: \(name)..."
                connectedDeviceLabel.textColor = NSColor.systemOrange
            } else {
                connectedDeviceLabel.stringValue = "Saved device not found (searching...)"
                connectedDeviceLabel.textColor = NSColor.systemOrange
            }
        } else {
            connectedDeviceLabel.stringValue = "No device selected"
            connectedDeviceLabel.textColor = .secondaryLabelColor
        }
    }

    private func updateClearButtonState() {
        clearSelectionButton.isEnabled = Preferences.shared.selectedDeviceUUID != nil
    }

    @objc func deviceSelected(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let uuid = selectedItem.representedObject as? String else {
            return
        }

        BluetoothManager.shared.connectToDevice(uuid: uuid)
        updateConnectedDeviceLabel()
        updateClearButtonState()
    }

    @objc func refreshButtonClicked(_ sender: NSButton) {
        discoveredDevices.removeAll()
        devicePopUpButton.removeAllItems()
        devicePopUpButton.addItem(withTitle: "Scanning...")
        devicePopUpButton.isEnabled = false
        BluetoothManager.shared.startScanningForSelection()
    }

    @objc func clearSelectionButtonClicked(_ sender: NSButton) {
        BluetoothManager.shared.clearDeviceSelection()
        updateDeviceDropdown()
        updateConnectedDeviceLabel()
        updateClearButtonState()

        // Resume scanning
        BluetoothManager.shared.startScanningForSelection()
    }

    func windowWillClose(_ notification: Notification) {
        BluetoothManager.shared.stopScanningForSelection()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        // Position window below the status bar item
        if let window = self.window,
           let appDelegate = NSApp.delegate as? AppDelegate,
           let button = appDelegate.statusBarItem.button,
           let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)

            // Position window so its top-right aligns with status bar button
            let windowFrame = window.frame
            let newX = screenRect.midX - (windowFrame.width / 2)
            let newY = screenRect.minY - windowFrame.height - 5

            window.setFrameOrigin(NSPoint(x: newX, y: newY))
        }

        AppDelegate.bringToFront(window: self.window!)

        // Start scanning when preferences window is shown
        BluetoothManager.shared.startScanningForSelection()
        discoveredDevices = BluetoothManager.shared.availablePeripherals
        updateDeviceDropdown()
        updateConnectedDeviceLabel()
        updateClearButtonState()
    }

    func updateLabels() {

        var standingPosition = Preferences.shared.standingPosition
        var sittingPosition = Preferences.shared.sittingPosition

        if !Preferences.shared.isMetric {
            standingPosition = standingPosition.convertToInches()
            sittingPosition = sittingPosition.convertToInches()
        }

        standingHeightField.stringValue = String(format: "%.1f", standingPosition)
        sittingHeightField.stringValue = String(format: "%.1f", sittingPosition)

        autoStandIntervalLabel.stringValue = String(format: "%.f",
            Preferences.shared.automaticStandPerHour / 60)
        autoStandInactiveLabel.stringValue = String(format: "%.f",
            Preferences.shared.automaticStandInactivity / 60)

        let autoEnabled = Preferences.shared.automaticStandEnabled
        autoStandInactiveLabel.textColor = autoEnabled ? .labelColor : .disabledControlTextColor
        autoStandIntervalLabel.textColor = autoEnabled ? .labelColor : .disabledControlTextColor
        autoStandIntervalStepper.isEnabled = autoEnabled
        autoStandInactiveStepper.isEnabled = autoEnabled

        var offsetPosition = Preferences.shared.positionOffset + (deskPosition ?? 0)
        if !Preferences.shared.isMetric {
            offsetPosition = offsetPosition.convertToInches()
        }

        currentHeightField?.stringValue = String(format: "%.1f", offsetPosition)
    }

    @IBAction func changeStandingHeightField(_ sender: NSTextField) {

        if var newPosition = Float(standingHeightField.stringValue) {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            Preferences.shared.standingPosition = newPosition
        }

    }

    @IBAction func changedSittingHeightField(_ sender: NSTextField) {

        if var newPosition = Float(sittingHeightField.stringValue) {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            Preferences.shared.sittingPosition = newPosition
        }
    }

    @IBAction func changedCurrentHeightField(_ sender: NSTextField) {

        if var newPosition = Float(sender.stringValue), let deskPosition = deskPosition {
            if !Preferences.shared.isMetric {
                newPosition = newPosition.convertToCentimeters()
            }
            let offset = newPosition - deskPosition
            Preferences.shared.positionOffset = offset
        }
    }

    @IBAction func toggledAutoStandCheckbox(_ sender: NSButton) {
        Preferences.shared.automaticStandEnabled = sender.state == .on
        updateLabels()
    }

    @IBAction func changedAutoStandStepper(_ sender: NSStepper) {
        let newInterval = Double(autoStandIntervalStepper.intValue)
        Preferences.shared.automaticStandPerHour = newInterval * 60
        updateLabels()
    }

    @IBAction func changedAutoStandInactiveStepper(_ sender: NSStepper) {
        let newInactive = Double(autoStandInactiveStepper.intValue)
        Preferences.shared.automaticStandInactivity = newInactive * 60
        updateLabels()
    }

    @IBAction func changedUnitsPopUpButton(_ sender: NSPopUpButton) {
        Preferences.shared.isMetric = sender.titleOfSelectedItem == "cm"
        updateLabels()
    }

    @IBAction func toggledOpenAtLoginCheckbox(_ sender: NSButton) {
        Preferences.shared.openAtLogin = sender.state == .on
    }
}
