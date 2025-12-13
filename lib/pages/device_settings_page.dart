import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ble_service.dart';

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  // State
  double _dimRatio = 100.0;
  bool _isDimRatioLoaded = false;
  
  double _micGain = 5.0; // Default to typical normal
  bool _isMicGainLoaded = false;

  // New State
  int? _batteryLevel;

  Timer? _debounce;
  Timer? _micGainDebounce;

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
  }

  Future<void> _loadInitialSettings() async {
    // Give time for connection to stabilize if just opened
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (!mounted) return;
    
    // Get initial values from BLE service
    final bleService = BleService();
    
    // Force read immediately instead of relying on cached values if any
    // Actually, getMicGain reads from characteristic.
    
    // Load Gain
    final gain = await bleService.getMicGain();
    
    // Load Dimming
    final dim = await bleService.getLedDimRatio();
    
    // Load Battery
    final batt = await bleService.getBatteryLevel();
    
    if (mounted) {
      setState(() {
        if (gain != null) {
          _micGain = (gain > 8 ? 8 : gain).toDouble();
          _isMicGainLoaded = true;
        }
        if (dim != null) {
          _dimRatio = dim.toDouble();
          _isDimRatioLoaded = true;
        }
        _batteryLevel = batt;
      });
    }
  }
  
  void _updateDimRatio(double value) {
    BleService().setLedDimRatio(value.toInt());
  }

  void _updateMicGain(double value) {
    BleService().setMicGain(value.toInt());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _micGainDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AppProvider>(context);
    final isConnected = provider.deviceState == DeviceConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
            if (isConnected) ...[
              const Text(
                'Customization',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Dimming
              const Text('Dimming', style: TextStyle(fontSize: 16)),
              Slider(
                value: _dimRatio,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_dimRatio.round()}%',
                onChanged: (val) {
                  setState(() => _dimRatio = val);
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 200), () => _updateDimRatio(val));
                },
              ),
              
              const SizedBox(height: 24),
              
              _buildSectionHeader(theme, 'Device Info'),
             Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoRow('Battery Level', '${_batteryLevel ?? "--"}%'),
                    // Device Info was requested to be removed previously, 
                    // but Battery is useful.
                  ],
                ),
              ),
            ),
             
            const SizedBox(height: 24),
            _buildSectionHeader(theme, 'Microphone Gain'),
              _buildMicGainCard(theme),
              
              const SizedBox(height: 32),
              
              // Audio Test
              const Text(
                'Debug',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
               child: ListTile(
                 title: const Text('Test Mic Audio'),
                 subtitle: const Text('Record 3s and playback'),
                 trailing: provider.isTestingAudio 
                   ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                   : const Icon(Icons.mic),
                 onTap: provider.isTestingAudio ? null : () {
                   provider.startAudioTest();
                 },
               ),
              ),
              
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await provider.disconnectDevice();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Disconnect'),
                ),
              ),
            ],
            if (!isConnected)
              const Center(child: Text("Device not connected")),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey),
                const SizedBox(width: 12),
                const Text('Device Info', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_batteryLevel != null)
                   Chip(
                     avatar: const Icon(Icons.battery_std, size: 16),
                     label: Text('$_batteryLevel%'),
                     backgroundColor: Colors.green.withOpacity(0.2),
                   ),
              ],
            ),
            const Divider(),
            _infoRow("Model", _deviceInfo['Model'] ?? 'Unknown'),
            _infoRow("Firmware", _deviceInfo['Firmware'] ?? 'Unknown'),
            _infoRow("Hardware", _deviceInfo['Hardware'] ?? 'Unknown'),
            _infoRow("Manufacturer", _deviceInfo['Manufacturer'] ?? 'Based Hardware'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }



  Widget _buildMicGainCard(ThemeData theme) {
    final currentLevel = _micGain.round();
    
    // Labels mapping
    String getLabel(int level) {
         if (level == 0) return 'Mute';
         if (level == 6) return '+20dB';
         // ... simplified for now
         return 'Level $level';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text('Mic Gain', style: TextStyle(fontWeight: FontWeight.bold)),
                 Text('${getLabel(currentLevel)}${currentLevel == 6 ? " (High)" : ""}'),
               ],
             ),
             const SizedBox(height: 8),
             const Text('High - for distant or soft voices', style: TextStyle(fontSize: 12, color: Colors.grey)),
             const SizedBox(height: 16),
             
             Slider(
               value: _micGain,
               min: 0,
               max: 8,
               divisions: 8,
               label: getLabel(currentLevel),
               onChanged: (val) {
                 setState(() => _micGain = val);
                 if (_micGainDebounce?.isActive ?? false) _micGainDebounce!.cancel();
                 _micGainDebounce = Timer(const Duration(milliseconds: 200), () => _updateMicGain(val));
               },
             ),
             
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 10),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: const [
                   Text('Mute', style: TextStyle(fontSize: 10)),
                   Text('+6dB', style: TextStyle(fontSize: 10)),
                   Text('Max', style: TextStyle(fontSize: 10)),
                 ],
               ),
             ),
             
             const SizedBox(height: 16),
             Row(
               children: [
                 _presetBtn('Quiet', 2),
                 const SizedBox(width: 8),
                 _presetBtn('Normal', 4),
                 const SizedBox(width: 8),
                 _presetBtn('High', 6),
               ],
             ),
           ],
        ),
      ),
    );
  }
  
  Widget _presetBtn(String label, double level) {
    final isSelected = _micGain == level;
    return Expanded(
      child: GestureDetector(
        onTap: () {
           setState(() => _micGain = level);
           _updateMicGain(level);
        },
        child: Container(
           padding: const EdgeInsets.symmetric(vertical: 8),
           decoration: BoxDecoration(
             border: Border.all(color: isSelected ? Colors.white : Colors.grey),
             borderRadius: BorderRadius.circular(8),
             color: isSelected ? Colors.white.withOpacity(0.1) : null,
           ),
           alignment: Alignment.center,
           child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey)),
        ),
      ),
    );
  }
}
