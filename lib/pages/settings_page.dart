/// Settings page for API keys and app configuration
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/app_provider.dart';
import '../services/ble_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import 'device_settings_page.dart';
import 'stats_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _deepgramController = TextEditingController();
  final _openaiController = TextEditingController();
  bool _obscureDeepgram = true;
  bool _obscureOpenai = true;

  @override
  void initState() {
    super.initState();
    _deepgramController.text = SettingsService.deepgramApiKey;
    _openaiController.text = SettingsService.openaiApiKey;
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Saved Device Section
          _buildSectionHeader('Connected Device'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                final savedName = SettingsService.savedDeviceName;
                final isConnected = provider.deviceState == DeviceConnectionState.connected;
                
                if (savedName.isEmpty) {
                  return ListTile(
                    contentPadding: const EdgeInsets.all(20),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.bluetooth_disabled, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    ),
                    title: const Text('No device saved'),
                    subtitle: const Text('Connect to a device to get started'),
                  );
                }
                
                return Column(
                  children: [
                    ListTile(
                      onTap: isConnected ? () {
                         Navigator.push(
                           context, 
                           MaterialPageRoute(builder: (_) => const DeviceSettingsPage())
                         );
                      } : null,
                      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isConnected ? const Color(0xFF6C5CE7).withOpacity(0.2) : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                          color: isConnected ? const Color(0xFF6C5CE7) : theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      title: Text(savedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(isConnected ? 'Connected • Tap to Configure' : 'Saved Device', 
                        style: TextStyle(color: isConnected ? const Color(0xFF6C5CE7) : null)),
                      trailing: isConnected ? Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await provider.forgetDevice();
                                setState(() {});
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                                foregroundColor: theme.colorScheme.onSurface,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Forget'),
                            ),
                          ),
                          if (!isConnected) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  provider.scanAndConnectToSavedDevice();
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('Connect'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          // Transcription Mode Section
          _buildSectionHeader('Transcription Engine'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildRadioTile(
                  title: 'Cloud (Deepgram)',
                  subtitle: 'Best quality, requires API key',
                  value: 'cloud',
                  groupValue: SettingsService.transcriptionMode,
                  icon: Icons.cloud_outlined,
                  onChanged: (value) => setState(() => SettingsService.transcriptionMode = value!),
                ),
                Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),

                _buildRadioTile(
                  title: 'Local (Whisper)',
                  subtitle: 'OpenAI Whisper, high accuracy',
                  value: 'whisper',
                  groupValue: SettingsService.transcriptionMode,
                  icon: Icons.record_voice_over_outlined,
                  onChanged: (value) => setState(() => SettingsService.transcriptionMode = value!),
                ),
                
                // Whisper model size selector
                if (SettingsService.useWhisper)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                    child: Row(
                      children: [
                        Text('Model Size:', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'tiny', label: Text('Tiny'), icon: Icon(Icons.speed, size: 16)),
                              ButtonSegment(value: 'base', label: Text('Base'), icon: Icon(Icons.high_quality, size: 16)),
                            ],
                            selected: {SettingsService.whisperModelSize},
                            onSelectionChanged: (values) => setState(() => SettingsService.whisperModelSize = values.first),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),

                _buildRadioTile(
                  title: 'Local (Sherpa-ONNX)',
                  subtitle: 'Real-time streaming ASR',
                  value: 'sherpa',
                  groupValue: SettingsService.transcriptionMode,
                  icon: Icons.bolt_outlined,
                  onChanged: (value) => setState(() => SettingsService.transcriptionMode = value!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),



          // Deepgram API Key
          if (SettingsService.useDeepgram) ...[
            _buildSectionHeader('Deepgram API Key'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _deepgramController,
                      obscureText: _obscureDeepgram,
                      decoration: InputDecoration(
                        hintText: 'Enter API Key',
                        labelText: 'API Key',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureDeepgram ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureDeepgram = !_obscureDeepgram),
                        ),
                      ),
                      onChanged: (value) {
                        SettingsService.deepgramApiKey = value;
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Get from console.deepgram.com',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // OpenAI API Key
          _buildSectionHeader('OpenAI API Key'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _openaiController,
                    obscureText: _obscureOpenai,
                    decoration: InputDecoration(
                      hintText: 'Enter API Key',
                      labelText: 'API Key',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureOpenai ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureOpenai = !_obscureOpenai),
                      ),
                    ),
                    onChanged: (value) {
                      SettingsService.openaiApiKey = value;
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For chat features. Get from platform.openai.com',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: SettingsService.openaiModel,
                    dropdownColor: const Color(0xFF2D2D2D),
                    decoration: const InputDecoration(
                      labelText: 'Model',
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    items: const [
                      DropdownMenuItem(value: 'gpt-5-nano', child: Text('GPT-5 Nano (cheapest)')),
                      DropdownMenuItem(value: 'gpt-5-mini', child: Text('GPT-5 Mini')),
                      DropdownMenuItem(value: 'gpt-5', child: Text('GPT-5')),
                      DropdownMenuItem(value: 'gpt-4.1', child: Text('GPT-4.1')),
                      DropdownMenuItem(value: 'gpt-4.1-mini', child: Text('GPT-4.1 Mini')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => SettingsService.openaiModel = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Notifications section
          _buildSectionHeader('Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Battery Low (50%)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Alert when Omi reaches 50%',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  value: SettingsService.notifyBatteryLow,
                  onChanged: (value) {
                    setState(() => SettingsService.notifyBatteryLow = value);
                  },
                  activeColor: const Color(0xFF6C5CE7),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Battery Critical (20%)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Alert when Omi reaches 20%',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  value: SettingsService.notifyBatteryCritical,
                  onChanged: (value) {
                    setState(() => SettingsService.notifyBatteryCritical = value);
                  },
                  activeColor: const Color(0xFF6C5CE7),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Task Reminders', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Reminders for scheduled tasks',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  value: SettingsService.notifyTaskReminders,
                  onChanged: (value) {
                    setState(() => SettingsService.notifyTaskReminders = value);
                  },
                  activeColor: const Color(0xFF6C5CE7),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Processing Alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Show "Processing: query" notifications',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  value: SettingsService.notifyProcessing,
                  onChanged: (value) {
                    setState(() => SettingsService.notifyProcessing = value);
                  },
                  activeColor: const Color(0xFF6C5CE7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Data section
          _buildSectionHeader('Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00b894).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.download, color: Color(0xFF00b894)),
                  ),
                  title: const Text('Export All Data', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Save conversations, memories & tasks as JSON',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  onTap: () => _exportAllData(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart, color: Color(0xFF6C5CE7)),
                  ),
                  title: const Text('Statistics', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('View your usage stats',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StatsPage()),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0984e3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cloud_outlined, color: Color(0xFF0984e3)),
                  ),
                  title: const Text('iCloud Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Sync data across devices',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                  value: SettingsService.icloudBackupEnabled,
                  onChanged: (value) {
                    setState(() => SettingsService.icloudBackupEnabled = value);
                    if (value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('iCloud backup enabled. Data will sync automatically.')),
                      );
                    }
                  },
                  activeColor: const Color(0xFF0984e3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // About section
          Center(
            child: Column(
              children: [
                Text('Omi Local', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Version 2.1.0 • Self-Hosted', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700, 
          fontSize: 12,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    final theme = Theme.of(context);
    
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      secondary: Icon(
        icon,
        color: isSelected ? const Color(0xFF6C5CE7) : theme.colorScheme.onSurface.withOpacity(0.5),
      ),
      activeColor: const Color(0xFF6C5CE7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  @override
  void dispose() {
    _deepgramController.dispose();
    _openaiController.dispose();
    super.dispose();
  }

  Future<void> _exportAllData(BuildContext context) async {
    // Store navigator before async operations
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // Get the render box for share positioning (needed on iPad)
    final box = context.findRenderObject() as RenderBox?;
    final sharePosition = box != null 
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing export...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Get all data
      final data = await DatabaseService.exportAllData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      
      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${tempDir.path}/omi_backup_$timestamp.json');
      await file.writeAsString(jsonString);
      
      // Close loading dialog
      navigator.pop();
      
      // Share the file with proper origin for iPad
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Omi Local Backup',
        sharePositionOrigin: sharePosition,
      );
    } catch (e) {
      // Close loading dialog if open
      navigator.pop();
      
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}
