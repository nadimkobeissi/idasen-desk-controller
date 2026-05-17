//
//  BluetoothManager.swift
//  Desk Controller
//
//  Created by David Williames on 11/1/21.
//

import Foundation
@preconcurrency import CoreBluetooth

struct DiscoveredDevice: Equatable, Sendable {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let identifier: UUID

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

@MainActor
class BluetoothManager: NSObject {

    var stopOnFirstConnection = true

    /// When true, scan for *every* named device (not just desks) and don't auto-connect.
    /// Used by the Preferences device picker.
    var scanningForSelection = false

    // Singleton for managing it all
    static let shared = BluetoothManager()

    var centralManager: CBCentralManager?

    var onCentralManagerStateChange: (CBCentralManager?) -> Void = { _ in }

    var onConnectedPeripheralChange: (CBPeripheral?) -> Void = { _ in  }
    private var connectPeripheralRSSI: NSNumber?

    /// The peripheral we are attempting to connect to (set in didDiscover)
    private var pendingPeripheral: CBPeripheral?

    /// The peripheral that is fully connected (set in didConnect, cleared in didDisconnect)
    private(set) var connectedPeripheral: CBPeripheral?

    /// All devices observed in the current scan (used by the device-picker UI).
    var onAvailableDevicesChange: ([DiscoveredDevice]) -> Void = { _ in }
    private(set) var availableDevices = [DiscoveredDevice]() {
        didSet {
            onAvailableDevicesChange(availableDevices)
        }
    }

    override init() {
        super.init()
        startScanning()
    }

    func startScanning() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func reconnect() {
        // Try connected peripheral first, then pending
        let peripheral = connectedPeripheral ?? pendingPeripheral
        guard let peripheral, peripheral.state == .disconnected else {
            return
        }
        centralManager?.connect(peripheral, options: nil)
    }

    // MARK: - Manual device selection (Preferences UI)

    /// Switch into "show everything with a name, don't auto-connect" mode.
    func startScanningForSelection() {
        scanningForSelection = true
        availableDevices = []
        if let central = centralManager, central.state == .poweredOn {
            central.stopScan()
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    /// Leave selection mode. Caller should follow up with `reconnect()` or
    /// `connectToDevice(uuid:)` to resume normal operation.
    func stopScanningForSelection() {
        scanningForSelection = false
        centralManager?.stopScan()
    }

    /// Persist the chosen device and connect to it. Disconnects any current peripheral first.
    func connectToDevice(uuid: String) {
        var target: CBPeripheral?
        if let match = availableDevices.first(where: { $0.identifier.uuidString == uuid }) {
            target = match.peripheral
        } else if let current = connectedPeripheral, current.identifier.uuidString == uuid {
            target = current
        }

        guard let peripheral = target else { return }

        scanningForSelection = false

        if let current = connectedPeripheral, current.state == .connected, current.identifier.uuidString != uuid {
            centralManager?.cancelPeripheralConnection(current)
        }

        Preferences.shared.selectedDeviceUUID = uuid
        pendingPeripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    /// Clear the manual selection and fall back to name-based auto-discovery.
    func clearDeviceSelection() {
        Preferences.shared.selectedDeviceUUID = nil
        if let current = connectedPeripheral, current.state == .connected {
            centralManager?.cancelPeripheralConnection(current)
        }
        connectedPeripheral = nil
        connectPeripheralRSSI = nil
    }
}

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            centralManager = central
            onCentralManagerStateChange(central)

            guard central.state == .poweredOn else {
                return
            }

            if let peripheral = connectedPeripheral ?? pendingPeripheral, peripheral.state == .disconnected {
                central.connect(peripheral, options: nil)
                return
            }
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Extract Sendable primitives BEFORE crossing into the MainActor closure —
        // `advertisementData` is `[String: Any]` and can't be sent across isolations.
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue

        MainActor.assumeIsolated {
            let cachedName = peripheral.name
            let displayName: String? = {
                if let localName, !localName.isEmpty { return localName }
                if let cachedName, !cachedName.isEmpty { return cachedName }
                return nil
            }()
            let looksLikeDesk = (cachedName?.lowercased().contains("desk") ?? false)
                || (localName?.lowercased().contains("desk") ?? false)

            // Record every named device when the picker UI is open.
            if scanningForSelection {
                guard let name = displayName else { return }
                let device = DiscoveredDevice(peripheral: peripheral,
                                              name: name,
                                              rssi: rssi,
                                              identifier: peripheral.identifier)
                if let idx = availableDevices.firstIndex(where: { $0.identifier == device.identifier }) {
                    availableDevices[idx] = device
                } else {
                    availableDevices.append(device)
                }
                availableDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return
            }

            // Normal auto-discovery path.
            guard pendingPeripheral != peripheral && connectedPeripheral != peripheral else {
                return
            }

            // If the user has chosen a specific device, only connect to that UUID.
            if let savedUUID = Preferences.shared.selectedDeviceUUID {
                guard peripheral.identifier.uuidString == savedUUID else { return }
            } else {
                guard looksLikeDesk else { return }
            }

            let isClosestMatchingPeripheral = (connectPeripheralRSSI != nil && rssi < connectPeripheralRSSI!.intValue)

            if pendingPeripheral == nil || isClosestMatchingPeripheral {
                central.connect(peripheral, options: nil)
                connectPeripheralRSSI = RSSI
                pendingPeripheral = peripheral
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard peripheral == pendingPeripheral else {
                return
            }

            if stopOnFirstConnection {
                central.stopScan()
            }

            // Promote pending → connected
            connectedPeripheral = peripheral
            pendingPeripheral = nil
            onConnectedPeripheralChange(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            if peripheral == connectedPeripheral {
                connectedPeripheral = nil
            }
            if peripheral == pendingPeripheral {
                pendingPeripheral = nil
            }
            connectPeripheralRSSI = nil

            onConnectedPeripheralChange(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            if peripheral == pendingPeripheral {
                pendingPeripheral = nil
            }
            connectPeripheralRSSI = nil

            onConnectedPeripheralChange(nil)
        }
    }

}
