/// Home page - device connection and live transcription
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ble_service.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';
import 'conversations_page.dart';
import 'chat_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DeviceTab(onNavigateToSettings: () => setState(() => _currentIndex = 3)),
          const ConversationsPage(),
          const ChatPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0A0A0A),
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: const Color(0xFF6C5CE7),
          unselectedItemColor: Colors.grey.withOpacity(0.5),
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_none_outlined),
              activeIcon: Icon(Icons.mic),
              label: 'Live',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class DeviceTab extends StatefulWidget {
  final VoidCallback? onNavigateToSettings;
  
  const DeviceTab({super.key, this.onNavigateToSettings});

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  bool _isScanning = false;
  List<BleDevice> _devices = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Omi Local'),
            backgroundColor: Colors.transparent,
            actions: [
              if (provider.batteryLevel != null)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        provider.batteryLevel! > 20
                            ? Icons.battery_full
                            : Icons.battery_alert,
                        size: 16,
                        color: provider.batteryLevel! > 20 ? Colors.greenAccent : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${provider.batteryLevel}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: _buildBody(provider),
        );
      },
    );
  }

  Widget _buildBody(AppProvider provider) {
    switch (provider.deviceState) {
      case DeviceConnectionState.disconnected:
        return _buildDisconnectedView(provider);
      case DeviceConnectionState.connecting:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF6C5CE7)),
              SizedBox(height: 16),
              Text('Connecting to Omi...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      case DeviceConnectionState.connected:
        return _buildConnectedView(provider);
    }
  }

  Widget _buildDisconnectedView(AppProvider provider) {
    final theme = Theme.of(context);
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Header
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6C5CE7).withOpacity(0.1),
              border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.2)),
            ),
            child: const Icon(Icons.mic, size: 48, color: Color(0xFF6C5CE7)),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Start Capturing',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect your Omi device\nto capture and transcribe conversations.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.6), height: 1.5),
        ),
        const SizedBox(height: 48),

        // API key warning
        if (!SettingsService.hasApiKeys) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Missing API Keys', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      const SizedBox(height: 4),
                      Text('Configure keys in Settings to enable transcription', 
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: widget.onNavigateToSettings,
                  child: const Text('Settings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // Connect to Omi Device
        _buildActionCard(
          title: 'Use Omi Device',
          subtitle: 'Connect via Bluetooth for hands-free recording',
          icon: Icons.bluetooth_audio,
          color: const Color(0xFF6C5CE7),
          onTap: _startScan,
        ),
        
        // Scanning overlay
        if (_isScanning) ...[
          const SizedBox(height: 32),
          const Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Scanning for devices...', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          ..._devices.map((device) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(device.name.isNotEmpty ? device.name : 'Unknown Device'),
              subtitle: Text(device.device.remoteId.str),
              trailing: ElevatedButton(
                onPressed: () => _connectToDevice(device, provider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Connect'),
              ),
            ),
          )).toList(),
        ],
      ],
    );
  }
  
  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isEnabled = onTap != null;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isEnabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: isEnabled ? color : Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? theme.colorScheme.onSurface : Colors.grey,
                    )),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(
                      fontSize: 12, 
                      color: theme.colorScheme.onSurface.withOpacity(0.5)
                    )),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildConnectedView(AppProvider provider) {
    return Column(
      children: [
        // Connected Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Omi Device Ready', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: provider.disconnectDevice,
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ),

        // Listening status banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: provider.isLoadingModel
              ? Colors.orange.withOpacity(0.15)
              : provider.isListening 
                  ? Colors.deepPurple.withOpacity(0.15) 
                  : Colors.grey.withOpacity(0.1),
          child: Row(
            children: [
              if (provider.isLoadingModel) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Loading transcription model...',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        'This may take a moment on first use',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (provider.isListening) ...[
                const _PulsingDot(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Listening...',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurpleAccent,
                        ),
                      ),
                      Text(
                        'Saves automatically after 2 min silence',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Manual save button
                if (provider.liveSegments.isNotEmpty)
                  TextButton.icon(
                    onPressed: provider.manualSaveConversation,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Now'),
                  ),
              ] else ...[
                const Icon(Icons.mic_off, color: Colors.grey),
                const SizedBox(width: 12),
                const Expanded(child: Text('Not listening')),
                ElevatedButton(
                  onPressed: SettingsService.hasApiKeys
                      ? () => _startListening(provider)
                      : null,
                  child: const Text('Start'),
                ),
              ],
            ],
          ),
        ),

        // Toggle button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: provider.isListening
                ? provider.stopListening
                : () => _startListening(provider),
            icon: Icon(provider.isListening ? Icons.stop : Icons.mic),
            label: Text(provider.isListening ? 'Stop Listening' : 'Start Listening'),
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.isListening ? Colors.red : Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
            ),
          ),
        ),

        // Live transcript
        if (provider.liveSegments.isNotEmpty)
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Current Conversation',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${provider.liveSegments.length} segments',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: provider.liveSegments.length,
                      reverse: false,
                      itemBuilder: (context, index) {
                        final segment = provider.liveSegments[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getSpeakerColor(segment.speakerId),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'S${segment.speakerId}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(segment.text)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (provider.isListening)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for speech...',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Color _getSpeakerColor(int speakerId) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    return colors[speakerId % colors.length];
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    final provider = context.read<AppProvider>();
    
    await for (final devices in provider.scanForDevices()) {
      setState(() => _devices = devices);
    }

    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BleDevice device, AppProvider provider) async {
    await provider.stopScan();
    await provider.connectToDevice(device);
  }

  Future<void> _startListening(AppProvider provider) async {
    try {
      await provider.startListening();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }


}

/// Pulsing red dot indicator for active recording
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(0.5 + _controller.value * 0.5),
          ),
        );
      },
    );
  }
}
