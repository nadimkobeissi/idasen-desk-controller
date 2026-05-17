//
//  ViewController.swift
//  Desk Controller
//
//  Created by David Williames on 10/1/21.
//

import Cocoa
@preconcurrency import CoreBluetooth

class ViewController: NSViewController {

    var controller: DeskController? = nil

    let bluetoothManager = BluetoothManager.shared

    @IBOutlet weak var messageLabel: NSTextField?
    @IBOutlet weak var containerStackView: NSStackView?

    @IBOutlet weak var currentPositionLabel: NSTextField?
    @IBOutlet weak var currentPositionDimenstionLabel: NSTextField?

    @IBOutlet weak var upButton: NSButton?
    @IBOutlet weak var downButton: NSButton?

    @IBOutlet weak var sitButton: NSButton?
    @IBOutlet weak var standButton: NSButton?

    // Status indicator
    @IBOutlet weak var statusIndicator: NSView?
    @IBOutlet weak var statusLabel: NSTextField?
    @IBOutlet weak var deviceNameLabel: NSTextField?

    weak var popover: NSPopover?


    let stopLabelString = "Stop moving"

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {

        bluetoothManager.onConnectedPeripheralChange = { [weak self] peripheral in
            self?.updateConnectionLabels()

            guard let peripheral = peripheral else {
                return
            }

            self?.setControllerFor(deskPeripheral: peripheral)
        }

        bluetoothManager.onCentralManagerStateChange = { [weak self] _ in
            self?.controller?.autoStand.unschedule()
            self?.updateConnectionLabels()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        preferredContentSize = NSSize(width: 260, height: 170)

        // Vibrant background to mimic the popover look on older macOS.
        // NSGlassEffectView (Tahoe-only) was the original choice; this works on macOS 13+.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        containerStackView?.isHidden = true
        messageLabel?.stringValue = ""

        if let indicator = statusIndicator {
            indicator.wantsLayer = true
            indicator.layer?.cornerRadius = indicator.frame.height / 2
        }

        statusLabel?.stringValue = "Connecting..."
        deviceNameLabel?.stringValue = ""

        currentPositionDimenstionLabel?.stringValue = Preferences.shared.isMetric ? "cm" : "in"

        if let position = controller?.desk.position {
            onDeskPositionChange(position)
        }

        updateConnectionLabels()
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }

    func updateConnectionLabels() {
        let isConnected = bluetoothManager.connectedPeripheral?.state == .connected

        containerStackView?.isHidden = !isConnected
        messageLabel?.isHidden = isConnected

        statusLabel?.stringValue = isConnected ? "Connected" : "Not connected"
        deviceNameLabel?.stringValue = bluetoothManager.connectedPeripheral?.name ?? ""
        statusIndicator?.layer?.backgroundColor = NSColor.red.cgColor

        if let centralManager = bluetoothManager.centralManager, let statusLabel = statusLabel {

            switch centralManager.state {
            case .poweredOff:
                statusLabel.stringValue = "Turning bluetooth on"
            case .poweredOn:
                statusLabel.stringValue = isConnected ? "Connected" : "Not connected"
                messageLabel?.stringValue = "Searching for your Desk... \n\nIf the desk hasn't connected to this Mac before, make sure to set it into pairing mode. \n\nOtherwise, make sure no other apps are currently connected to it."

                statusIndicator?.layer?.backgroundColor = isConnected ? NSColor.green.cgColor : NSColor.orange.cgColor

                if !isConnected {
                    deviceNameLabel?.stringValue = "Searching for nearby desks"
                }
            case .resetting:
                statusLabel.stringValue = "Reconnecting"
                statusIndicator?.layer?.backgroundColor = NSColor.orange.cgColor
            case .unauthorized:
                statusLabel.stringValue = "Unauthorized"
            case .unknown:
                statusLabel.stringValue = "Unknown status"
            case .unsupported:
                statusLabel.stringValue = "Bluetooth not supported"
            @unknown default:
                break
            }

            if centralManager.authorization == .denied {
                statusLabel.stringValue = "Bluetooth access was denied"

                messageLabel?.stringValue = "Bluetooth access was denied, but is vital for this application. To re-prompt the permission; delete and re-install this mac application."
            }
        }
    }

    func setControllerFor(deskPeripheral: CBPeripheral) {
        let desk = DeskPeripheral(peripheral: deskPeripheral)

        controller = DeskController(desk: desk)
        controller?.onPositionChange({ [weak self] deskPosition in
            self?.onDeskPositionChange(deskPosition)
        })

        controller?.onCurrentMovingDirectionChange = { [weak self] movingDirection in
            if movingDirection == .none {
                self?.sitButton?.title = "Move to sit"
                self?.standButton?.title = "Move to stand"
            }
        }

    }

    func onDeskPositionChange(_ newPosition: Float) {
        var convertedPosition = newPosition + Preferences.shared.positionOffset

        if !Preferences.shared.isMetric {
            convertedPosition = convertedPosition.convertToInches()
        }

        currentPositionLabel?.stringValue = "\(Int(convertedPosition.rounded()))"

        sitButton?.isEnabled = abs((Preferences.shared.sittingPosition - Preferences.shared.positionOffset) - newPosition) > 0.5
        standButton?.isEnabled = abs((Preferences.shared.standingPosition - Preferences.shared.positionOffset) - newPosition) > 0.5
    }

    func reconnect() {

        if bluetoothManager.connectedPeripheral == nil {
            bluetoothManager.startScanning()
        }

        if let position = controller?.desk.position {
            onDeskPositionChange(position)
        }

    }

    @IBAction func moveUpClicked(_ sender: TouchButton) {
        guard let controller = controller else {
            return
        }

        if !sender.isPressed {
            controller.stopMoving()
        } else if let position = controller.desk.position, Preferences.shared.standingPosition > position {
            controller.moveToPosition(.stand)
        } else {
            controller.moveUp()
        }
    }

    @IBAction func moveDownClicked(_ sender: TouchButton) {
        guard let controller = controller else {
            return
        }

        if !sender.isPressed {
            controller.stopMoving()
        } else if let position = controller.desk.position, Preferences.shared.sittingPosition < position {
            controller.moveToPosition(.sit)
        } else {
            controller.moveDown()
        }
    }

    @IBAction func sit(_ sender: Any) {
        guard let button = sitButton, let controller else {
            return
        }

        if button.title == stopLabelString {
            controller.stopMoving()
        } else {
            button.title = stopLabelString
            controller.moveToPosition(.sit)
        }
    }

    @IBAction func stand(_ sender: Any) {
        guard let button = standButton, let controller else {
            return
        }

        if button.title == stopLabelString {
            controller.stopMoving()
        } else {
            button.title = stopLabelString
            controller.moveToPosition(.stand)
        }
    }

    @IBAction func showPreferences(_ sender: Any) {
        PreferencesWindowController.sharedInstance.showWindow(nil)
        PreferencesWindowController.sharedInstance.deskController = controller
        popover?.performClose(self)
    }
}
