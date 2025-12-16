/// SD Card Sync Page
/// Allows users to sync audio data from Omi device's SD card
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/ble_service.dart';
import '../services/sdcard_sync_service.dart';

class SdCardSyncPage extends StatefulWidget {
  const SdCardSyncPage({super.key});

  @override
  State<SdCardSyncPage> createState() => _SdCardSyncPageState();
}

class _SdCardSyncPageState extends State<SdCardSyncPage> with TickerProviderStateMixin {
  bool _isChecking = false;
  bool _isSyncing = false;
  bool _isProcessing = false;
  bool _isClearing = false;
  SdCardWal? _pendingWal;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _lastSyncedFile;
  String? _transcriptResult;
  
  // Local synced files
  List<SyncedAudioFile> _syncedFiles = [];
  String? _processingFilePath;
  
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Check for pending data and load synced files on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForData();
      _loadSyncedFiles();
    });
  }
  
  Future<void> _loadSyncedFiles() async {
    final files = await SdCardSyncService.getSyncedFiles();
    setState(() {
      _syncedFiles = files;
    });
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  Future<void> _checkForData() async {
    final provider = context.read<AppProvider>();
    if (!provider.hasStorageSupport) {
      setState(() {
        _statusMessage = 'SD card storage not supported on this device';
      });
      return;
    }
    
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking for data...';
    });
    
    final wal = await provider.sdCardSyncService?.checkForPendingData();
    
    setState(() {
      _isChecking = false;
      _pendingWal = wal;
      if (wal != null) {
        _statusMessage = 'Found ${wal.durationFormatted} of audio (${wal.sizeFormatted})';
      } else {
        _statusMessage = 'No pending data on SD card';
      }
    });
  }
  
  Future<void> _startSync() async {
    final provider = context.read<AppProvider>();
    
    setState(() {
      _isSyncing = true;
      _progress = 0.0;
      _statusMessage = 'Starting sync...';
      _transcriptResult = null;
    });
    
    await provider.sdCardSyncService?.startSync(
      onProgress: (progress, status) {
        setState(() {
          _progress = progress;
          _statusMessage = status;
        });
      },
      onComplete: (filePath, durationSeconds) async {
        setState(() {
          _isSyncing = false;
          _lastSyncedFile = filePath;
          _statusMessage = 'Sync complete!';
          _progress = 1.0;
        });
        
        // Refresh files list
        await _loadSyncedFiles();
        
        // Refresh to check for more data
        await _checkForData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Audio synced! Tap the file to process it.'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'Process Now',
                textColor: Colors.white,
                onPressed: () => _processAudio(filePath, durationSeconds),
              ),
            ),
          );
        }
      },
      onError: (error) {
        setState(() {
          _isSyncing = false;
          _statusMessage = 'Error: $error';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }
  
  Future<void> _processAudio(String filePath, int durationSeconds) async {
    setState(() {
      _isProcessing = true;
      _processingFilePath = filePath;
      _statusMessage = 'Transcribing audio...';
    });
    
    try {
      final provider = context.read<AppProvider>();
      final transcript = await provider.processLocalAudioFile(filePath);
      
      setState(() {
        _isProcessing = false;
        _processingFilePath = null;
        _transcriptResult = transcript;
        _statusMessage = 'Processing complete!';
      });
      
      // Delete the audio file after processing
      await SdCardSyncService.deleteAudioFile(filePath);
      await _loadSyncedFiles();
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingFilePath = null;
        _statusMessage = 'Transcription failed: $e';
      });
    }
  }
  
  Future<void> _processIndividualFile(SyncedAudioFile file) async {
    setState(() {
      _isProcessing = true;
      _processingFilePath = file.filePath;
      _statusMessage = 'Transcribing ${file.fileName}...';
    });
    
    try {
      final provider = context.read<AppProvider>();
      final transcript = await provider.processLocalAudioFile(file.filePath);
      
      setState(() {
        _isProcessing = false;
        _processingFilePath = null;
        _transcriptResult = transcript;
        _statusMessage = 'Processing complete!';
      });
      
      // Mark as processed and refresh
      await _loadSyncedFiles();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio processed and saved to conversations'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingFilePath = null;
        _statusMessage = 'Transcription failed: $e';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processing failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _deleteFile(SyncedAudioFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${file.fileName}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await SdCardSyncService.deleteSyncedFile(file.filePath);
      if (success) {
        await _loadSyncedFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File deleted')),
          );
        }
      }
    }
  }
  
  Future<void> _deleteAllFiles() async {
    if (_syncedFiles.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Files'),
        content: Text('Delete all ${_syncedFiles.length} synced files?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final deleted = await SdCardSyncService.deleteAllSyncedFiles();
      await _loadSyncedFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $deleted files')),
        );
      }
    }
  }
  
  Future<void> _clearDeviceStorage() async {
    final provider = context.read<AppProvider>();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Device Storage'),
        content: const Text(
          'Clear all data from your Omi device\'s SD card?\n\n'
          'This will delete all unsynced recordings on the device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear Storage'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        _isClearing = true;
        _statusMessage = 'Clearing device storage...';
      });
      
      final success = await provider.sdCardSyncService?.clearDeviceStorage() ?? false;
      
      setState(() {
        _isClearing = false;
        _statusMessage = success ? 'Device storage cleared' : 'Failed to clear storage';
      });
      
      if (success) {
        await _checkForData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device storage cleared'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }
  
  Future<void> _cancelSync() async {
    final provider = context.read<AppProvider>();
    await provider.sdCardSyncService?.cancelSync();
    
    setState(() {
      _isSyncing = false;
      _progress = 0.0;
      _statusMessage = 'Sync cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SD Card Sync'),
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (!provider.hasStorageSupport) {
            return _buildNoSupportView();
          }
          
          return _buildSyncView(provider);
        },
      ),
    );
  }
  
  Widget _buildNoSupportView() {
    final provider = context.read<AppProvider>();
    final isConnected = provider.deviceState == DeviceConnectionState.connected;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sd_card_alert,
                size: 64,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isConnected ? 'SD Card Not Supported' : 'Device Not Connected',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isConnected 
                  ? 'Your Omi device doesn\'t have SD card storage.\n\nThis feature requires an Omi DevKit 2 or newer with SD card hardware and firmware v2.0+.'
                  : 'Connect to your Omi device first to check for SD card storage.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (!isConnected)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.bluetooth),
                label: const Text('Connect Device'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSyncView(AppProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Card
          _buildStatusCard(),
          
          const SizedBox(height: 24),
          
          // Progress Indicator (when syncing)
          if (_isSyncing || _isProcessing || _isClearing)
            _buildProgressCard(),
          
          // Pending Data Card (from device)
          if (_pendingWal != null && !_isSyncing && !_isProcessing && !_isClearing)
            _buildPendingDataCard(),
          
          // No Data on Device Card
          if (_pendingWal == null && !_isChecking && !_isSyncing && !_isProcessing && !_isClearing)
            _buildNoDataCard(),
          
          const SizedBox(height: 24),
          
          // Local Synced Files Section
          if (_syncedFiles.isNotEmpty && !_isSyncing && !_isProcessing)
            _buildSyncedFilesSection(),
          
          // Transcript Result
          if (_transcriptResult != null)
            _buildTranscriptCard(),
          
          const SizedBox(height: 24),
          
          // Device Actions
          if (provider.hasStorageSupport && !_isSyncing && !_isProcessing && !_isClearing)
            _buildDeviceActionsSection(),
          
          const SizedBox(height: 24),
          
          // Info Section
          _buildInfoSection(),
        ],
      ),
    );
  }
  
  Widget _buildStatusCard() {
    Color statusColor;
    IconData statusIcon;
    
    if (_isSyncing) {
      statusColor = const Color(0xFF6C5CE7);
      statusIcon = Icons.sync;
    } else if (_isProcessing) {
      statusColor = Colors.amber;
      statusIcon = Icons.memory;
    } else if (_pendingWal != null) {
      statusColor = Colors.green;
      statusIcon = Icons.sd_card;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.check_circle;
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(
                    _isSyncing ? 0.2 + (_pulseController.value * 0.3) : 0.2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  statusIcon,
                  color: statusColor,
                  size: 28,
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSyncing ? 'Syncing...' : 
                  _isProcessing ? 'Processing...' :
                  _pendingWal != null ? 'Data Available' : 'All Synced',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          if (_isChecking)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
  
  Widget _buildProgressCard() {
    String statusText;
    Color progressColor;
    bool showCancel = false;
    
    if (_isClearing) {
      statusText = 'Clearing device storage...';
      progressColor = Colors.red;
    } else if (_isProcessing) {
      statusText = 'Transcribing audio...';
      progressColor = Colors.amber;
    } else {
      statusText = 'Syncing from SD card...';
      progressColor = const Color(0xFF6C5CE7);
      showCancel = true;
    }
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // Circular Progress
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: _isClearing || _isProcessing ? null : _progress,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                if (!_isClearing && !_isProcessing)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_pendingWal?.syncEtaSeconds != null)
                        Text(
                          _formatEta(_pendingWal!.syncEtaSeconds!),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),
                    ],
                  )
                else
                  Icon(
                    _isClearing ? Icons.delete_forever : Icons.memory,
                    size: 48,
                    color: progressColor,
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (showCancel && _isSyncing)
            TextButton.icon(
              onPressed: _cancelSync,
              icon: const Icon(Icons.cancel, color: Colors.red),
              label: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
  
  Widget _buildPendingDataCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.audiotrack,
                  color: Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio Recording',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_pendingWal!.durationFormatted} • ${_pendingWal!.sizeFormatted}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          ElevatedButton.icon(
            onPressed: _startSync,
            icon: const Icon(Icons.download),
            label: const Text('Sync & Process'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: const Color(0xFF6C5CE7),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNoDataCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'All Caught Up!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending audio on your Omi\'s SD card',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _checkForData,
            icon: const Icon(Icons.refresh),
            label: const Text('Check Again'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTranscriptCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_snippet, color: Color(0xFFA29BFE)),
              const SizedBox(width: 12),
              const Text(
                'Transcript',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  // Copy to clipboard
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _transcriptResult ?? '',
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSyncedFilesSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00b894).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder, color: Color(0xFF00b894), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Synced Files',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_syncedFiles.length} file${_syncedFiles.length == 1 ? '' : 's'} on your phone',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_syncedFiles.length > 1)
                  TextButton(
                    onPressed: _deleteAllFiles,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete All'),
                  ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // File list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _syncedFiles.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = _syncedFiles[index];
              final isProcessing = _processingFilePath == file.filePath;
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.audiotrack, color: Color(0xFF6C5CE7), size: 20),
                ),
                title: Text(
                  file.durationFormatted,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${file.sizeFormatted} • ${file.dateFormatted}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
                trailing: isProcessing
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Process button
                          IconButton(
                            onPressed: () => _processIndividualFile(file),
                            icon: const Icon(Icons.play_arrow, color: Color(0xFF00b894)),
                            tooltip: 'Process & Transcribe',
                          ),
                          // Delete button
                          IconButton(
                            onPressed: () => _deleteFile(file),
                            icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildDeviceActionsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red.shade300, size: 20),
              const SizedBox(width: 8),
              Text(
                'Device Storage',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Clear all unsynced data from your Omi device. Use this if you want to start fresh without syncing.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearDeviceStorage,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Clear Device Storage'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade300, size: 20),
              const SizedBox(width: 8),
              Text(
                'About SD Card Sync',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'When your Omi device records audio while disconnected from your phone, '
            'it stores the data on its SD card. Use this feature to:\n\n'
            '• Download offline recordings\n'
            '• Transcribe and save to your history\n'
            '• Clear storage for new recordings',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s remaining';
    }
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}m ${secs}s remaining';
  }
}

