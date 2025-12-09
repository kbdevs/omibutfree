/// BLE service for Omi device connection
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Omi device UUIDs (extracted from original app)
const String omiServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
const String audioDataStreamCharacteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
const String audioCodecCharacteristicUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
const String batteryServiceUuid = '180f';
const String batteryLevelCharacteristicUuid = '2a19';

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
}

class BleDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;

  BleDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });
}

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _audioCharacteristic;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _connectionSubscription;

  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  DeviceConnectionState get state => _state;

  final _stateController = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get stateStream => _stateController.stream;

  final _audioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioController.stream;

  final _batteryController = StreamController<int>.broadcast();
  Stream<int> get batteryStream => _batteryController.stream;

  bool get isConnected => _state == DeviceConnectionState.connected;
  String? get connectedDeviceId => _connectedDevice?.remoteId.str;
  String? get connectedDeviceName => _connectedDevice?.platformName;

  /// Try to connect to a previously saved device by its remote ID
  Future<bool> connectToSavedDevice(String deviceId) async {
    if (deviceId.isEmpty) return false;
    
    try {
      debugPrint('Attempting to reconnect to saved device: $deviceId');
      
      // Wait for Bluetooth adapter to be ready (skip unknown state)
      await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 10), onTimeout: () => BluetoothAdapterState.off);

      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        debugPrint('Bluetooth is not on for auto-connect: $state');
        return false;
      }
      
      // Create device from ID and try to connect
      final device = BluetoothDevice.fromId(deviceId);
      return await connect(device);
    } catch (e) {
      debugPrint('Failed to reconnect to saved device: $e');
      return false;
    }
  }


  /// Scan for Omi devices
  Stream<List<BleDevice>> scanForDevices({Duration timeout = const Duration(seconds: 15)}) async* {
    List<BleDevice> devices = [];

    try {
      // Wait for Bluetooth adapter to be ready (skip unknown state)
      await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);

      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        debugPrint('Bluetooth is not on: $state');
        return;
      }

      debugPrint('Starting BLE scan...');
      
      await FlutterBluePlus.startScan(
        timeout: timeout,
        // Don't filter - show all devices so user can pick
        // withServices: [Guid(omiServiceUuid)],
      );

      await for (final results in FlutterBluePlus.scanResults) {
        devices = results
            .where((r) => r.device.platformName.isNotEmpty) // Only show devices with names
            .map((r) => BleDevice(
              device: r.device,
              name: r.device.platformName,
              rssi: r.rssi,
            )).toList();
        
        // Sort by signal strength
        devices.sort((a, b) => b.rssi.compareTo(a.rssi));
        
        debugPrint('Found ${devices.length} devices');
        yield devices;
      }
    } catch (e) {
      debugPrint('Scan error: $e');
      yield [];
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  /// Connect to Omi device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _state = DeviceConnectionState.connecting;
      _stateController.add(_state);

      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services
      final services = await device.discoverServices();
      
      // Find audio characteristic
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == omiServiceUuid.toLowerCase()) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == audioDataStreamCharacteristicUuid.toLowerCase()) {
              _audioCharacteristic = char;
              break;
            }
          }
        }
      }

      if (_audioCharacteristic == null) {
        debugPrint('Audio characteristic not found');
        await disconnect();
        return false;
      }

      _state = DeviceConnectionState.connected;
      _stateController.add(_state);
      
      debugPrint('Connected to Omi device');
      return true;
    } catch (e) {
      debugPrint('Failed to connect: $e');
      _state = DeviceConnectionState.disconnected;
      _stateController.add(_state);
      return false;
    }
  }

  /// Start listening for audio data
  Future<void> startAudioStream() async {
    if (_audioCharacteristic == null) return;

    try {
      await _audioCharacteristic!.setNotifyValue(true);
      _audioSubscription = _audioCharacteristic!.onValueReceived.listen((value) {
        if (value.isNotEmpty) {
          _audioController.add(Uint8List.fromList(value));
        }
      });
      debugPrint('Audio stream started');
    } catch (e) {
      debugPrint('Failed to start audio stream: $e');
    }
  }

  /// Stop audio stream
  Future<void> stopAudioStream() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      await _audioCharacteristic?.setNotifyValue(false);
    } catch (e) {
      debugPrint('Error stopping audio stream: $e');
    }
  }

  /// Get battery level
  Future<int?> getBatteryLevel() async {
    if (_connectedDevice == null) return null;

    try {
      final services = await _connectedDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == batteryServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == batteryLevelCharacteristicUuid) {
              final value = await char.read();
              if (value.isNotEmpty) {
                return value[0];
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to read battery: $e');
    }
    return null;
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await stopAudioStream();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
    
    _connectedDevice = null;
    _audioCharacteristic = null;
    _state = DeviceConnectionState.disconnected;
    _stateController.add(_state);
  }

  void _onDisconnected() {
    _connectedDevice = null;
    _audioCharacteristic = null;
    _state = DeviceConnectionState.disconnected;
    _stateController.add(_state);
    debugPrint('Device disconnected');
  }

  void dispose() {
    _stateController.close();
    _audioController.close();
    _batteryController.close();
  }
}
