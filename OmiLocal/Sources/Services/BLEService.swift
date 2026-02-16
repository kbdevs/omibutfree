import Foundation
import CoreBluetooth
import Combine

class BLEService: NSObject, ObservableObject {
    static let omiServiceUUID = CBUUID(string: "19b10000-e8f2-537e-4f6c-d104768a1214")
    static let audioDataStreamCharacteristicUUID = CBUUID(string: "19b10001-e8f2-537e-4f6c-d104768a1214")
    static let batteryServiceUUID = CBUUID(string: "180f")
    static let batteryLevelCharacteristicUUID = CBUUID(string: "2a19")
    static let buttonServiceUUID = CBUUID(string: "23ba7924-0000-1000-7450-346eac492e92")
    static let buttonTriggerCharacteristicUUID = CBUUID(string: "23ba7925-0000-1000-7450-346eac492e92")
    static let storageServiceUUID = CBUUID(string: "30295780-4301-eabd-2904-2849adfeae43")
    static let storageDataStreamCharacteristicUUID = CBUUID(string: "30295781-4301-eabd-2904-2849adfeae43")
    
    @Published var deviceState: DeviceConnectionState = .disconnected
    @Published var audioData: Data = Data()
    @Published var buttonData: [UInt8] = []
    @Published var batteryLevel: Int?
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var audioCharacteristic: CBCharacteristic?
    private var buttonCharacteristic: CBCharacteristic?
    private var storageCharacteristic: CBCharacteristic?
    
    private var scanStream: AsyncStream<[DiscoveredDevice]>?
    private var scanContinuation: AsyncStream<[DiscoveredDevice]>.Continuation?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scanForDevices() -> AsyncStream<[DiscoveredDevice]> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
            
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
            
            continuation.onTermination = { _ in
                self.centralManager.stopScan()
            }
        }
    }
    
    func stopScan() {
        centralManager.stopScan()
        scanContinuation?.finish()
    }
    
    func connect(_ device: DiscoveredDevice) async -> Bool {
        guard let peripheral = findPeripheral(by: device.id) else { return false }
        deviceState = .connecting
        
        return await withCheckedContinuation { continuation in
            centralManager.connect(peripheral, options: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.deviceState == .connecting {
                    self?.deviceState = .disconnected
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func connectToSavedDevice(_ deviceId: String) async -> Bool {
        guard let peripheral = findPeripheral(by: deviceId) else { return false }
        deviceState = .connecting
        centralManager.connect(peripheral, options: nil)
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.deviceState == .connecting {
                    self?.deviceState = .disconnected
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private var peripherals: [CBPeripheral] = []
    
    private func findPeripheral(by id: String) -> CBPeripheral? {
        peripherals.first { $0.identifier.uuidString == id }
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        audioCharacteristic = nil
        buttonCharacteristic = nil
        storageCharacteristic = nil
        deviceState = .disconnected
    }
    
    func startAudioStream() async {
        guard let characteristic = audioCharacteristic, let peripheral = connectedPeripheral else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }
    
    func stopAudioStream() async {
        guard let characteristic = audioCharacteristic, let peripheral = connectedPeripheral else { return }
        peripheral.setNotifyValue(false, for: characteristic)
    }
    
    func hasStorageSupport() async -> Bool {
        return storageCharacteristic != nil
    }
    
    func triggerHaptic(_ level: Int) {
        // Would send command to device
    }
    
    func getBatteryLevel() async -> Int? {
        guard let peripheral = connectedPeripheral else { return nil }
        
        return await withCheckedContinuation { continuation in
            if let service = peripheral.services?.first(where: { $0.uuid == Self.batteryServiceUUID }),
               let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelCharacteristicUUID }) {
                peripheral.readValue(for: characteristic)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    continuation.resume(returning: self.batteryLevel)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

extension BLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            break
        case .poweredOff, .unauthorized, .unsupported:
            deviceState = .disconnected
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !peripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            peripherals.append(peripheral)
        }
        
        let name = peripheral.name ?? "Unknown Device"
        if name.lowercased().contains("omi") {
            let device = DiscoveredDevice(
                id: peripheral.identifier.uuidString,
                name: name,
                rssi: RSSI.intValue
            )
            scanContinuation?.yield([device])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([
            Self.omiServiceUUID,
            Self.batteryServiceUUID,
            Self.buttonServiceUUID,
            Self.storageServiceUUID
        ])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        deviceState = .disconnected
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        audioCharacteristic = nil
        buttonCharacteristic = nil
        storageCharacteristic = nil
        deviceState = .disconnected
    }
}

extension BLEService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == Self.audioDataStreamCharacteristicUUID {
                audioCharacteristic = characteristic
            } else if characteristic.uuid == Self.buttonTriggerCharacteristicUUID {
                buttonCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == Self.storageDataStreamCharacteristicUUID {
                storageCharacteristic = characteristic
            } else if characteristic.uuid == Self.batteryLevelCharacteristicUUID {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == Self.audioDataStreamCharacteristicUUID {
            DispatchQueue.main.async {
                self.audioData = data
            }
        } else if characteristic.uuid == Self.buttonTriggerCharacteristicUUID {
            DispatchQueue.main.async {
                self.buttonData = Array(data)
            }
        } else if characteristic.uuid == Self.batteryLevelCharacteristicUUID {
            DispatchQueue.main.async {
                self.batteryLevel = Int(data.first ?? 0)
            }
        }
    }
}
