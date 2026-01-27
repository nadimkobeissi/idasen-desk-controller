//
//  BluetoothManager.swift
//  Desk Controller
//
//  Created by David Williames on 11/1/21.
//

import Foundation
import CoreBluetooth

// Model for discovered devices to display in UI
struct DiscoveredDevice: Equatable {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let identifier: UUID

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

class BluetoothManager: NSObject {

    var stopOnFirstConnection = true

    // When true, scan for all devices without auto-connecting (for device selection UI)
    var scanningForSelection = false
    
    // Singleton for managing it all
    static let shared = BluetoothManager()
    
    var centralManager: CBCentralManager?
    
    var onCentralManagerStateChange: (CBCentralManager?) -> Void = { _ in }
    
    var onConnectedPeripheralChange: (CBPeripheral?) -> Void = { _ in  }
    private var connectPeripheralRSSI: NSNumber?
    var connectedPeripheral: CBPeripheral? // Or is currently being connected to

    
    // Store all discovered devices for selection UI
    var onAvailablePeripheralsChange: ([DiscoveredDevice]) -> Void = { _ in }
    private(set) var availablePeripherals = [DiscoveredDevice]() {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onAvailablePeripheralsChange(self.availablePeripherals)
            }
        }
    }
    
    
    // It will only match if the Name contains 'Desk' in it
    // Check both peripheral.name and advertisementData since the name may only be
    // available in advertisement data during initial pairing/discovery
    var matchCriteria: (CBPeripheral, [String: Any]?) -> Bool = { peripheral, advertisementData in
        // Check peripheral.name (cached from previous connections)
        if let name = peripheral.name, name.contains("Desk") {
            return true
        }
        // Check advertisement data local name (available during initial discovery)
        if let advertisementData = advertisementData,
           let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           localName.contains("Desk") {
            return true
        }
        return false
    }
    
    
    override init() {
        super.init()
        startScanning()
    }
    
    func startScanning() {
        if centralManager == nil {
            let queue = DispatchQueue(label: "BT_queue")
            centralManager = CBCentralManager(delegate: self, queue: queue)
        }
    }
    
    func reconnect() {
        guard let peripheral = connectedPeripheral,
              peripheral.state == .disconnected else {
                  return
        }

        centralManager?.connect(peripheral, options: nil)
    }

    /// Connect to a specific device by UUID
    func connectToDevice(uuid: String) {
        // Find the device in available peripherals
        var peripheral: CBPeripheral?

        if let device = availablePeripherals.first(where: { $0.identifier.uuidString == uuid }) {
            peripheral = device.peripheral
        } else if let connected = connectedPeripheral, connected.identifier.uuidString == uuid {
            // Already have this peripheral (maybe from a previous connection)
            peripheral = connected
        }

        guard let devicePeripheral = peripheral else {
            // Device not found
            print("Device with UUID \(uuid) not found")
            return
        }

        // Stop selection mode
        scanningForSelection = false

        // Disconnect from current if connected to a different device
        if let current = connectedPeripheral, current.state == .connected, current.identifier.uuidString != uuid {
            centralManager?.cancelPeripheralConnection(current)
        }

        // Save selection and connect
        Preferences.shared.selectedDeviceUUID = uuid
        connectedPeripheral = devicePeripheral
        centralManager?.connect(devicePeripheral, options: nil)
    }

    /// Start scanning for device selection (all devices, no auto-connect)
    func startScanningForSelection() {
        scanningForSelection = true
        availablePeripherals.removeAll()

        // Restart scanning
        centralManager?.stopScan()
        if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    /// Stop scanning for selection and resume normal operation
    func stopScanningForSelection() {
        scanningForSelection = false
    }

    /// Clear the saved device selection
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
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        centralManager = central
        onCentralManagerStateChange(central)
        
        guard central.state == .poweredOn else {
            return
        }
        
        if let connectedPeripheral = connectedPeripheral, connectedPeripheral.state == .disconnected {
            // Reconnect to any previous desk
            central.connect(connectedPeripheral, options: nil)
            return
        }
        // Start scanning for all peripherals
        central.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // print("Discovered peripheral: \(peripheral) • \(advertisementData) • \(RSSI)")

        // Get display name from advertisement data or peripheral
        let displayName: String?
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            displayName = localName
        } else if let name = peripheral.name, !name.isEmpty {
            displayName = name
        } else {
            displayName = nil  // No name available
        }

        // Only track devices that have a name (skip anonymous devices)
        guard let name = displayName else {
            return
        }

        // Create discovered device record
        let device = DiscoveredDevice(
            peripheral: peripheral,
            name: name,
            rssi: RSSI.intValue,
            identifier: peripheral.identifier
        )

        // Update or add to available peripherals
        if let index = availablePeripherals.firstIndex(where: { $0.identifier == device.identifier }) {
            // Update with new name if we now have one (device may have started advertising name)
            availablePeripherals[index] = device
        } else {
            availablePeripherals.append(device)
        }

        // Sort alphabetically by name for stable ordering
        availablePeripherals.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // If scanning for selection mode, don't auto-connect
        if scanningForSelection {
            return
        }

        // Check if we have a saved device to connect to
        if let savedUUID = Preferences.shared.selectedDeviceUUID {
            if peripheral.identifier.uuidString == savedUUID && connectedPeripheral != peripheral {
                // Connect to saved device
                central.connect(peripheral, options: nil)
                connectedPeripheral = peripheral
                connectPeripheralRSSI = RSSI
            }
            return
        }

        // No saved device - use name-based matching (backward compatibility)
        guard connectedPeripheral != peripheral, matchCriteria(peripheral, advertisementData) else {
            return
        }

        let isClosestMatchingPeripheral = (connectPeripheralRSSI != nil && RSSI.intValue > connectPeripheralRSSI!.intValue)

        // If it's the first match or it's the closest one; update the connect peripheral
        if connectedPeripheral == nil || isClosestMatchingPeripheral {
            // Connect to the new one
            central.connect(peripheral, options: nil)

            connectPeripheralRSSI = RSSI
            connectedPeripheral = peripheral
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // print("Connected to peripheral: \(peripheral)")

        // Make sure it's the one we're connecting to
        guard peripheral == connectedPeripheral else {
            // print("Not the one we're tracking")
            return
        }

        // Save the connected device UUID so preferences UI recognizes it
        if Preferences.shared.selectedDeviceUUID == nil {
            Preferences.shared.selectedDeviceUUID = peripheral.identifier.uuidString
        }

        if stopOnFirstConnection {
            central.stopScan()
        }

        onConnectedPeripheralChange(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // print("Disconnected to peripheral: \(peripheral)")
        
        // Make sure it's the one we're connecting to
        guard peripheral == connectedPeripheral else {
            // print("Not the one we're tracking")
            return
        }
        
        connectPeripheralRSSI = nil
        connectedPeripheral = nil
        
        onConnectedPeripheralChange(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Make sure it's the one we're connecting to
        guard peripheral == connectedPeripheral else {
            // print("Not the one we're tracking")
            return
        }
        
        connectPeripheralRSSI = nil
        connectedPeripheral = nil
        
        onConnectedPeripheralChange(nil)
    }
  
}
