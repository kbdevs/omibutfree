/// Settings page for API keys and app configuration
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ble_service.dart';
import '../services/settings_service.dart';

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
                      subtitle: Text(isConnected ? 'Connected & Ready' : 'Saved Device', 
                        style: TextStyle(color: isConnected ? const Color(0xFF6C5CE7) : null)),
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
                  subtitle: 'Offline, standard accuracy',
                  value: 'whisper',
                  groupValue: SettingsService.transcriptionMode,
                  icon: Icons.smartphone_outlined,
                  onChanged: (value) => setState(() => SettingsService.transcriptionMode = value!),
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

          // Whisper Model Selection
          if (SettingsService.useWhisper) ...[
            _buildSectionHeader('Whisper Model Size'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: SettingsService.whisperModel,
                      decoration: const InputDecoration(
                        labelText: 'Select Model',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      dropdownColor: const Color(0xFF2D2D2D),
                      items: const [
                        DropdownMenuItem(value: 'tiny', child: Text('Tiny (Fastest)')),
                        DropdownMenuItem(value: 'base', child: Text('Base (Balanced)')),
                        DropdownMenuItem(value: 'small', child: Text('Small (Better)')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium (Best)')),
                      ],
                      onChanged: (value) => setState(() => SettingsService.whisperModel = value!),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Larger models are more accurate but drain battery faster.',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

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
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // About section
          Center(
            child: Column(
              children: [
                Text('Omi Local', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Version 1.0.0 • Self-Hosted', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
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
}
