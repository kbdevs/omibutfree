import Foundation
import CoreBluetooth
import Combine

class BLEService: NSObject, ObservableObject {
    static let omiServiceUUID = CBUUID(string: "19b10000-e8f2-537e-4f6c-d104768a1214")
    static let audioDataStreamCharacteristicUUID = CBUUID(string: "19b10001-e8f2-537e-4f6c-d104768a1214")
    static let audioCodecCharacteristicUUID = CBUUID(string: "19b10002-e8f2-537e-4f6c-d104768a1214")
    static let batteryServiceUUID = CBUUID(string: "180f")
    static let batteryLevelCharacteristicUUID = CBUUID(string: "2a19")
    static let buttonServiceUUID = CBUUID(string: "23ba7924-0000-1000-7450-346eac492e92")
    static let buttonTriggerCharacteristicUUID = CBUUID(string: "23ba7925-0000-1000-7450-346eac492e92")
    static let storageServiceUUID = CBUUID(string: "30295780-4301-eabd-2904-2849adfeae43")
    static let storageDataStreamCharacteristicUUID = CBUUID(string: "30295781-4301-eabd-2904-2849adfeae43")
    static let storageReadControlCharacteristicUUID = CBUUID(string: "30295782-4301-eabd-2904-2849adfeae43")
    static let settingsServiceUUID = CBUUID(string: "19b10010-e8f2-537e-4f6c-d104768a1214")
    static let settingsDimRatioCharacteristicUUID = CBUUID(string: "19b10011-e8f2-537e-4f6c-d104768a1214")
    static let settingsMicGainCharacteristicUUID = CBUUID(string: "19b10012-e8f2-537e-4f6c-d104768a1214")
    static let speakerServiceUUID = CBUUID(string: "cab1ab95-2ea5-4f4d-bb56-874b72cfc984")
    static let speakerDataStreamCharacteristicUUID = CBUUID(string: "cab1ab96-2ea5-4f4d-bb56-874b72cfc984")
    
    @Published var deviceState: DeviceConnectionState = .disconnected
    @Published var batteryLevel: Int?
    
    let audioDataSubject = PassthroughSubject<Data, Never>()
    var audioDataPublisher: AnyPublisher<Data, Never> {
        audioDataSubject.eraseToAnyPublisher()
    }
    
    let buttonDataSubject = PassthroughSubject<[UInt8], Never>()
    var buttonDataPublisher: AnyPublisher<[UInt8], Never> {
        buttonDataSubject.eraseToAnyPublisher()
    }
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var audioCharacteristic: CBCharacteristic?
    private var buttonCharacteristic: CBCharacteristic?
    private var storageCharacteristic: CBCharacteristic?
    private var storageReadControlCharacteristic: CBCharacteristic?
    
    private var peripherals: [CBPeripheral] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scanForDevices() -> AsyncStream<[DiscoveredDevice]> {
        AsyncStream { continuation in
            if self.centralManager.state == .poweredOn {
                self.centralManager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                self.centralManager.stopScan()
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                self.centralManager.stopScan()
            }
        }
    }
    
    func stopScan() {
        centralManager.stopScan()
    }
    
    func connect(_ device: DiscoveredDevice) async -> Bool {
        guard let peripheral = findPeripheral(by: device.id) else { return false }
        deviceState = .connecting
        
        return await withCheckedContinuation { continuation in
            centralManager.connect(peripheral, options: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self else { return }
                if self.deviceState == .connecting {
                    self.deviceState = .disconnected
                    continuation.resume(returning: false)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                if self.deviceState == .connected {
                    continuation.resume(returning: true)
                }
            }
        }
    }
    
    func connectToSavedDevice(_ deviceId: String) async -> Bool {
        return await connect(DiscoveredDevice(id: deviceId, name: "Saved Device", rssi: 0))
    }
    
    private func findPeripheral(by id: String) -> CBPeripheral? {
        if let peripheral = peripherals.first(where: { $0.identifier.uuidString == id }) {
            return peripheral
        }
        
        let retrievedPeripherals = centralManager.retrievePeripherals(withIdentifiers: [UUID(uuidString: id)].compactMap { $0 })
        if let peripheral = retrievedPeripherals.first {
            peripherals.append(peripheral)
            return peripheral
        }
        
        return nil
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        audioCharacteristic = nil
        buttonCharacteristic = nil
        storageCharacteristic = nil
        storageReadControlCharacteristic = nil
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
        guard let peripheral = connectedPeripheral else { return }
        
        peripheral.discoverServices([Self.speakerServiceUUID])
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.speakerServiceUUID }) else { return }
            
            peripheral.discoverCharacteristics(nil, for: service)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let char = service.characteristics?.first(where: { $0.uuid == Self.speakerDataStreamCharacteristicUUID }) else { return }
                
                peripheral.writeValue(Data([UInt8(level)]), for: char, type: .withoutResponse)
            }
        }
    }
    
    func getBatteryLevel() async -> Int? {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.batteryServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelCharacteristicUUID }) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            peripheral.readValue(for: characteristic)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                continuation.resume(returning: self?.batteryLevel)
            }
        }
    }
    
    func getMicGain() async -> Int? {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.settingsServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.settingsMicGainCharacteristicUUID }) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            peripheral.readValue(for: characteristic)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume(returning: nil)
            }
        }
    }
    
    func setMicGain(_ gain: Int) async {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.settingsServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.settingsMicGainCharacteristicUUID }) else {
            return
        }
        
        peripheral.writeValue(Data([UInt8(gain)]), for: characteristic, type: .withResponse)
    }
    
    func getLedDimRatio() async -> Int? {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.settingsServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.settingsDimRatioCharacteristicUUID }) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            peripheral.readValue(for: characteristic)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume(returning: nil)
            }
        }
    }
    
    func setLedDimRatio(_ ratio: Int) async {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.settingsServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.settingsDimRatioCharacteristicUUID }) else {
            return
        }
        
        peripheral.writeValue(Data([UInt8(ratio)]), for: characteristic, type: .withResponse)
    }
    
    func getStorageList() async -> [Int] {
        guard let peripheral = connectedPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.storageServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.storageReadControlCharacteristicUUID }) else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            peripheral.readValue(for: characteristic)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                continuation.resume(returning: [])
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
            print("Discovered Omi device: \(name)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([
            Self.omiServiceUUID,
            Self.batteryServiceUUID,
            Self.buttonServiceUUID,
            Self.storageServiceUUID,
            Self.settingsServiceUUID,
            Self.speakerServiceUUID
        ])
        
        deviceState = .connected
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        deviceState = .disconnected
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        audioCharacteristic = nil
        buttonCharacteristic = nil
        storageCharacteristic = nil
        storageReadControlCharacteristic = nil
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
            } else if characteristic.uuid == Self.storageReadControlCharacteristicUUID {
                storageReadControlCharacteristic = characteristic
            } else if characteristic.uuid == Self.batteryLevelCharacteristicUUID {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == Self.audioDataStreamCharacteristicUUID {
            audioDataSubject.send(data)
        } else if characteristic.uuid == Self.buttonTriggerCharacteristicUUID {
            buttonDataSubject.send(Array(data))
        } else if characteristic.uuid == Self.batteryLevelCharacteristicUUID {
            batteryLevel = Int(data.first ?? 0)
        }
    }
}
