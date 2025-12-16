/// SD Card Sync Service for Omi device
/// Handles reading audio data from Omi's SD card storage, syncing to phone,
/// transcribing, and deleting from device.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'ble_service.dart';

/// Represents a WAL (Write-Ahead Log) file from SD card
enum WalStatus {
  pending,    // Found on device, not yet synced
  syncing,    // Currently being synced
  synced,     // Successfully synced
  failed,     // Sync failed
}

class SdCardWal {
  final int timerStart;
  final BleAudioCodec codec;
  final int storageOffset;
  final int storageTotalBytes;
  int seconds;
  WalStatus status;
  String? localFilePath;
  
  /// Progress 0.0 - 1.0
  double syncProgress = 0.0;
  
  /// Estimated time remaining in seconds
  int? syncEtaSeconds;
  
  SdCardWal({
    required this.timerStart,
    required this.codec,
    required this.storageOffset,
    required this.storageTotalBytes,
    required this.seconds,
    this.status = WalStatus.pending,
    this.localFilePath,
  });
  
  String get id => 'sdcard_$timerStart';
  
  int get bytesToSync => storageTotalBytes - storageOffset;
  
  String get durationFormatted {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }
  
  String get sizeFormatted {
    final bytes = bytesToSync;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Represents a locally synced audio file
class SyncedAudioFile {
  final String filePath;
  final String fileName;
  final int sizeBytes;
  final DateTime createdAt;
  final int? durationSeconds;
  final BleAudioCodec? codec;
  bool isProcessed;
  
  SyncedAudioFile({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.createdAt,
    this.durationSeconds,
    this.codec,
    this.isProcessed = false,
  });
  
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  String get durationFormatted {
    if (durationSeconds == null) return 'Unknown';
    final mins = durationSeconds! ~/ 60;
    final secs = durationSeconds! % 60;
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }
  
  String get dateFormatted {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
  }
}

/// Sync progress listener callback
typedef SyncProgressCallback = void Function(double progress, String status);

/// Sync complete callback - provides path to saved audio file
typedef SyncCompleteCallback = void Function(String filePath, int durationSeconds);

/// Error callback
typedef SyncErrorCallback = void Function(String error);

class SdCardSyncService {
  final BleService _bleService;
  
  StreamSubscription? _storageSubscription;
  
  // Current sync state
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  
  SdCardWal? _currentWal;
  SdCardWal? get currentWal => _currentWal;
  
  // Sync callbacks
  SyncProgressCallback? onProgress;
  SyncCompleteCallback? onComplete;
  SyncErrorCallback? onError;
  
  // Chunking constants
  static const int chunkSizeFrames = 6000; // ~60 seconds at 100fps
  
  SdCardSyncService(this._bleService);
  
  /// Check if SD card has data to sync
  Future<SdCardWal?> checkForPendingData() async {
    try {
      final storageList = await _bleService.getStorageList();
      if (storageList.isEmpty) {
        debugPrint('No storage data available');
        return null;
      }
      
      final totalBytes = storageList[0];
      if (totalBytes <= 0) {
        debugPrint('Storage is empty');
        return null;
      }
      
      final storageOffset = storageList.length >= 2 ? storageList[1] : 0;
      if (storageOffset > totalBytes) {
        debugPrint('Bad storage state: offset > total');
        return null;
      }
      
      // Get audio codec
      final codec = await _bleService.getAudioCodec();
      
      // Calculate duration - minimum 10 seconds to be worth syncing
      final bytesToSync = totalBytes - storageOffset;
      final framesPerSecond = codec.getFramesPerSecond();
      final frameLengthBytes = codec.getFramesLengthInBytes();
      final seconds = (bytesToSync / frameLengthBytes) ~/ framesPerSecond;
      
      if (seconds < 10) {
        debugPrint('Not enough data to sync: ${seconds}s');
        return null;
      }
      
      final timerStart = DateTime.now().millisecondsSinceEpoch ~/ 1000 - seconds;
      
      final wal = SdCardWal(
        timerStart: timerStart,
        codec: codec,
        storageOffset: storageOffset,
        storageTotalBytes: totalBytes,
        seconds: seconds,
      );
      
      debugPrint('Found SD card data: ${wal.durationFormatted} (${wal.sizeFormatted})');
      return wal;
      
    } catch (e) {
      debugPrint('Error checking SD card data: $e');
      return null;
    }
  }
  
  /// Start syncing SD card data
  Future<void> startSync({
    SyncProgressCallback? onProgress,
    SyncCompleteCallback? onComplete,
    SyncErrorCallback? onError,
  }) async {
    if (_isSyncing) {
      onError?.call('Sync already in progress');
      return;
    }
    
    this.onProgress = onProgress;
    this.onComplete = onComplete;
    this.onError = onError;
    
    // Check for pending data
    final wal = await checkForPendingData();
    if (wal == null) {
      onError?.call('No data to sync');
      return;
    }
    
    _currentWal = wal;
    _isSyncing = true;
    wal.status = WalStatus.syncing;
    
    onProgress?.call(0.0, 'Starting sync...');
    
    try {
      await _performSync(wal);
    } catch (e) {
      wal.status = WalStatus.failed;
      _isSyncing = false;
      onError?.call('Sync failed: $e');
      debugPrint('Sync error: $e');
    }
  }
  
  Future<void> _performSync(SdCardWal wal) async {
    debugPrint('Starting SD card sync: offset=${wal.storageOffset}, total=${wal.storageTotalBytes}');
    
    final startTime = DateTime.now();
    int currentOffset = wal.storageOffset;
    List<List<int>> frames = [];
    
    final completer = Completer<void>();
    bool hasError = false;
    bool firstDataReceived = false;
    Timer? timeoutTimer;
    
    // Start storage stream listener
    await _bleService.startStorageStream();
    
    _storageSubscription = _bleService.storageStream.listen((List<int> value) async {
      if (value.isEmpty || hasError) return;
      
      // Cancel timeout on first data
      if (!firstDataReceived) {
        firstDataReceived = true;
        timeoutTimer?.cancel();
        debugPrint('First data received from SD card');
      }
      
      // Process command responses (single byte)
      if (value.length == 1) {
        final cmd = value[0];
        debugPrint('Storage command response: $cmd');
        
        if (cmd == 0) {
          debugPrint('Storage: Ready to receive');
        } else if (cmd == 3) {
          debugPrint('Storage: Bad file size');
        } else if (cmd == 4) {
          debugPrint('Storage: File is empty');
          if (!completer.isCompleted) completer.complete();
        } else if (cmd == 100) {
          debugPrint('Storage: Transfer complete');
          if (!completer.isCompleted) completer.complete();
        } else {
          debugPrint('Storage: Error code $cmd');
          if (!completer.isCompleted) completer.complete();
        }
        return;
      }
      
      // Process audio data packets
      if (value.length == 83) {
        // Standard packet: 3 bytes header + 80 bytes data
        final amount = value[3];
        frames.add(value.sublist(4, 4 + amount));
        currentOffset += 80;
      } else if (value.length == 440) {
        // Multi-frame packet
        int packageOffset = 0;
        while (packageOffset < value.length - 1) {
          final packageSize = value[packageOffset];
          if (packageSize == 0) {
            packageOffset++;
            continue;
          }
          if (packageOffset + 1 + packageSize >= value.length) break;
          
          final frame = value.sublist(packageOffset + 1, packageOffset + 1 + packageSize);
          frames.add(frame);
          packageOffset += packageSize + 1;
        }
        currentOffset += value.length;
      }
      
      // Update progress
      final progress = (currentOffset - wal.storageOffset) / 
                       (wal.storageTotalBytes - wal.storageOffset);
      wal.syncProgress = progress.clamp(0.0, 1.0);
      
      // Calculate ETA
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed > 0 && progress > 0) {
        final remaining = ((elapsed / progress) * (1 - progress)).round();
        wal.syncEtaSeconds = remaining;
      }
      
      onProgress?.call(wal.syncProgress, 'Syncing: ${(wal.syncProgress * 100).toInt()}%');
    });
    
    // Start transfer from device
    await _bleService.writeToStorage(1, 0, wal.storageOffset);
    
    // Timeout for first data (5 seconds)
    timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (!firstDataReceived && !completer.isCompleted) {
        hasError = true;
        completer.completeError(TimeoutException('No data received from SD card'));
      }
    });
    
    // Wait for transfer to complete
    try {
      await completer.future.timeout(
        Duration(seconds: wal.seconds + 60), // Give extra time beyond expected duration
        onTimeout: () {
          throw TimeoutException('Transfer timed out');
        },
      );
    } finally {
      await _storageSubscription?.cancel();
      await _bleService.stopStorageStream();
      timeoutTimer?.cancel();
    }
    
    if (hasError) {
      throw Exception('Transfer failed');
    }
    
    // Save frames to file
    if (frames.isNotEmpty) {
      final filePath = await _saveFramesToFile(frames, wal);
      wal.localFilePath = filePath;
      wal.status = WalStatus.synced;
      
      debugPrint('Saved ${frames.length} frames to: $filePath');
      
      // Clear data from device
      await _clearDeviceStorage(wal);
      
      _isSyncing = false;
      onProgress?.call(1.0, 'Sync complete!');
      onComplete?.call(filePath, wal.seconds);
    } else {
      _isSyncing = false;
      throw Exception('No frames received');
    }
  }
  
  /// Save audio frames to a local file
  Future<String> _saveFramesToFile(List<List<int>> frames, SdCardWal wal) async {
    final directory = await getApplicationDocumentsDirectory();
    final filename = 'sdcard_audio_${wal.codec.name}_16000_1_${wal.timerStart}.bin';
    final filePath = '${directory.path}/$filename';
    
    final file = File(filePath);
    final sink = file.openWrite();
    
    for (final frame in frames) {
      // Format: <4 bytes length><data>
      sink.add([
        frame.length & 0xFF,
        (frame.length >> 8) & 0xFF,
        (frame.length >> 16) & 0xFF,
        (frame.length >> 24) & 0xFF,
      ]);
      sink.add(frame);
    }
    
    await sink.close();
    
    return filePath;
  }
  
  /// Clear synced data from device
  Future<void> _clearDeviceStorage(SdCardWal wal) async {
    try {
      // Command 1 = clear/acknowledge processed data
      // Parameters: fileNum (1 for SD card), command (1 = clear), offset (0)
      await _bleService.writeToStorage(1, 1, 0);
      debugPrint('Cleared SD card storage after syncing ${wal.storageTotalBytes} bytes');
    } catch (e) {
      debugPrint('Warning: Failed to clear device storage: $e');
      // Don't throw - data is already saved locally
    }
  }
  
  /// Cancel ongoing sync
  Future<void> cancelSync() async {
    if (!_isSyncing) return;
    
    await _storageSubscription?.cancel();
    await _bleService.stopStorageStream();
    
    if (_currentWal != null) {
      _currentWal!.status = WalStatus.failed;
    }
    
    _isSyncing = false;
    _currentWal = null;
    
    debugPrint('Sync cancelled');
  }
  
  /// Read and decode a synced audio file
  /// Returns PCM audio data ready for transcription
  static Future<Uint8List?> readAudioFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('Audio file not found: $filePath');
        return null;
      }
      
      final bytes = await file.readAsBytes();
      final frames = <List<int>>[];
      
      int offset = 0;
      while (offset < bytes.length - 4) {
        final length = bytes[offset] |
                      (bytes[offset + 1] << 8) |
                      (bytes[offset + 2] << 16) |
                      (bytes[offset + 3] << 24);
        offset += 4;
        
        if (offset + length > bytes.length) break;
        
        frames.add(bytes.sublist(offset, offset + length));
        offset += length;
      }
      
      debugPrint('Read ${frames.length} frames from audio file');
      
      // Concatenate all frames
      final allBytes = <int>[];
      for (final frame in frames) {
        allBytes.addAll(frame);
      }
      
      return Uint8List.fromList(allBytes);
    } catch (e) {
      debugPrint('Error reading audio file: $e');
      return null;
    }
  }
  
  /// Delete a synced audio file
  static Future<void> deleteAudioFile(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        debugPrint('Deleted audio file: $filePath');
      }
    } catch (e) {
      debugPrint('Error deleting audio file: $e');
    }
  }
  
  /// Get list of synced audio files with metadata
  static Future<List<SyncedAudioFile>> getSyncedFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = <SyncedAudioFile>[];
    
    for (final entity in directory.listSync()) {
      if (entity is File && entity.path.contains('sdcard_audio_')) {
        try {
          final stat = await entity.stat();
          final fileName = entity.path.split('/').last;
          
          // Parse codec and timestamp from filename
          // Format: sdcard_audio_{codec}_16000_1_{timestamp}.bin
          BleAudioCodec? codec;
          int? durationSeconds;
          
          if (fileName.contains('opus')) {
            codec = BleAudioCodec.opus;
            // Estimate duration: ~100 bytes per second for opus
            durationSeconds = stat.size ~/ 800;
          } else if (fileName.contains('pcm8')) {
            codec = BleAudioCodec.pcm8;
            durationSeconds = stat.size ~/ 16000;
          }
          
          files.add(SyncedAudioFile(
            filePath: entity.path,
            fileName: fileName,
            sizeBytes: stat.size,
            createdAt: stat.modified,
            durationSeconds: durationSeconds,
            codec: codec,
          ));
        } catch (e) {
          debugPrint('Error reading file info: $e');
        }
      }
    }
    
    // Sort by date, newest first
    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    return files;
  }
  
  /// Delete a specific synced audio file
  static Future<bool> deleteSyncedFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted synced file: $filePath');
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
    return false;
  }
  
  /// Delete all synced audio files
  static Future<int> deleteAllSyncedFiles() async {
    final files = await getSyncedFiles();
    int deleted = 0;
    
    for (final file in files) {
      if (await deleteSyncedFile(file.filePath)) {
        deleted++;
      }
    }
    
    return deleted;
  }
  
  /// Clear all data from device SD card
  Future<bool> clearDeviceStorage() async {
    try {
      // Command 1 = clear storage
      final success = await _bleService.writeToStorage(1, 1, 0);
      if (success) {
        debugPrint('Cleared device SD card storage');
      }
      return success;
    } catch (e) {
      debugPrint('Error clearing device storage: $e');
      return false;
    }
  }
  
  void dispose() {
    _storageSubscription?.cancel();
  }
}

