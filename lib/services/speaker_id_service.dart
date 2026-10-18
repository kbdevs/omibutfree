// On-device speaker recognition using Sherpa-ONNX voice embeddings.
//
// How it works
//  1. Deepgram does the transcription and tells us "speaker 0 said X from
//     12.3s to 15.8s" (diarization, but with anonymous numbers).
//  2. We keep a rolling copy of the same audio ([PcmRingBuffer]) and cut out
//     the clip for each segment.
//  3. A small speaker-embedding model turns each clip into a vector that
//     captures the voice. Clips from the same person land close together.
//  4. Vectors are compared (cosine similarity) with the voices of people the
//     user has labeled before; a close match gives the speaker a name.
//  5. When the user labels a speaker, their clips are saved for that person,
//     so recognition improves the more you label.
//
// Everything here runs locally. No audio or voice data is sent anywhere
// beyond what Deepgram already receives for transcription.
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'settings_service.dart';
import 'speaker_matching.dart';

class SpeakerIdService {
  SpeakerIdService() {
    matcher = SpeakerMatcher(threshold: SettingsService.speakerMatchThreshold);
    session = SpeakerSession(
      matcher: matcher,
      maxEmbeddingsPerSpeaker: maxEmbeddingsPerSpeaker,
    );
  }

  // --- Model -------------------------------------------------------------

  /// English speaker-embedding model (WeSpeaker ResNet34, trained on VoxCeleb).
  ///
  /// License note: the file is hosted by the sherpa-onnx author on Hugging Face
  /// (no model card there). WeSpeaker's docs state that its pretrained models
  /// follow the license of their training dataset; VoxCeleb is published under
  /// CC BY 4.0 'for research purposes'. Read those terms yourself before using
  /// or redistributing the model. See README 'Credits'.
  ///
  /// ~26 MB. Other models from the same repo can be swapped in here; saved
  /// voice samples from a different model are ignored automatically because
  /// their vector length differs, but note that two models can share a vector
  /// length, so clear the People list when switching models.
  static const String modelFileName = 'wespeaker_en_voxceleb_resnet34.onnx';
  // Pinned to one commit of the model repo (not `main`), and the downloaded
  // file is checked against [modelSha256], so a changed or truncated file is
  // rejected instead of being loaded by native code.
  static const String modelCommit = '0743f301363dec56491a490f6d6cbc9d67f9a3bf';
  static const String modelUrl =
      'https://huggingface.co/csukuangfj/speaker-embedding-models/resolve/$modelCommit/$modelFileName';
  static const String modelSha256 =
      '5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94';
  static const int modelSizeBytes = 26534365;

  /// How long a download may go without receiving anything before it fails.
  static const Duration downloadTimeout = Duration(seconds: 30);

  // --- Tuning ------------------------------------------------------------

  /// Clips shorter than this give unreliable voice vectors, so they are skipped.
  /// (Measured with the model above on one two-speaker recording: 1.5 s clips
  /// wrongly matched strangers ~20% of the time at the default threshold;
  /// 2 s clips did not. Real-world audio may need a longer floor.)
  static const double minSegmentSeconds = 2.0;

  /// Only the first part of very long segments is used (keeps CPU time bounded).
  static const double maxSegmentSeconds = 15;

  static const int maxEmbeddingsPerSpeaker = 12;

  // --- State -------------------------------------------------------------

  /// Rolling copy of the audio sent to Deepgram. Stream time 0 = first byte.
  final PcmRingBuffer buffer = PcmRingBuffer();
  late final SpeakerMatcher matcher;
  late final SpeakerSession session;

  sherpa.SpeakerEmbeddingExtractor? _extractor;
  Future<void>? _initFuture;
  int _lastFrameBytes = 0;
  bool _disposed = false;

  /// True once the model is loaded and [embed] can be used.
  bool get isReady => _extractor != null;

  /// Vector length of the loaded model (0 until ready).
  int get dim => _extractor?.dim ?? 0;

  // --- Setup -------------------------------------------------------------

  Future<String> _modelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/speaker_models/$modelFileName';
  }

  /// Downloads the model on first use, then loads it. Safe to call repeatedly;
  /// concurrent calls share one run. Throws if the download/load fails.
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(StateError('SpeakerIdService was disposed'));
    }
    return _initFuture ??= _initialize().catchError((e) {
      _initFuture = null; // allow a retry
      throw e;
    });
  }

  Future<void> _initialize() async {
    final path = await _modelPath();
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() != modelSizeBytes) {
      await _download(file);
    }
    // dispose() may have run while the download was in progress; loading now
    // would create an extractor that nothing frees.
    if (_disposed) return;
    loadModelFromFile(path);
  }

  /// Load an already-downloaded model file. (Split out so tests can supply a
  /// local model without going through the download.)
  @visibleForTesting
  void loadModelFromFile(String path) {
    if (_disposed) return;
    sherpa.initBindings();
    _extractor = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(
        model: path,
        numThreads: 2,
        debug: false,
      ),
    );
    debugPrint('Speaker model loaded (embedding dim: ${_extractor!.dim})');
  }

  /// File names of partial downloads running in this process right now.
  static final Set<String> _activePartials = {};

  /// Deletes `<model file>.<n>.part` files left behind when an earlier run of
  /// the app was stopped mid-download (the normal cleanup only runs when a
  /// download fails inside the app). Names in [keep], the downloads still
  /// running, are left alone.
  @visibleForTesting
  static void deleteStalePartials(File target, {Set<String> keep = const {}}) {
    final dir = target.parent;
    if (!dir.existsSync()) return;
    final prefix = '${target.uri.pathSegments.last}.';
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(prefix) &&
          name.endsWith('.part') &&
          !keep.contains(name)) {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _download(File target) async {
    debugPrint('Downloading speaker model from $modelUrl');
    await target.parent.create(recursive: true);
    deleteStalePartials(target, keep: _activePartials);
    // Unique per download, so overlapping downloads cannot write to one file.
    final partial = File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    final partialName = partial.uri.pathSegments.last;
    _activePartials.add(partialName);
    final client = http.Client();
    IOSink? sink;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(modelUrl)))
          .timeout(downloadTimeout);
      if (response.statusCode != 200) {
        throw Exception('Speaker model download failed (HTTP ${response.statusCode})');
      }
      sink = partial.openWrite();
      // A stalled connection fails the download (and a later call retries).
      await response.stream.timeout(downloadTimeout).pipe(sink);
      if (partial.lengthSync() != modelSizeBytes ||
          await sha256OfFile(partial) != modelSha256) {
        throw Exception('Speaker model download is incomplete or not the expected file');
      }
      await partial.rename(target.path);
    } catch (e) {
      // pipe() only closes the sink when the stream finishes, so close it here
      // when the download failed or timed out part-way.
      try {
        await sink?.close();
      } catch (_) {}
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    } finally {
      _activePartials.remove(partialName);
      client.close();
    }
  }

  /// Lower-case hex SHA-256 of [file].
  @visibleForTesting
  static Future<String> sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  // --- Audio in ----------------------------------------------------------

  /// Mirror of the audio sent to Deepgram. Call this for every chunk that is
  /// actually sent, with the decoded PCM16 (or null if decoding failed, in
  /// which case silence is inserted so the timeline stays aligned).
  void feedPcm(Uint8List? pcm) {
    if (pcm != null) {
      _lastFrameBytes = pcm.length;
      buffer.add(pcm);
    } else {
      // Keep the timeline aligned with what was sent to Deepgram. If no frame
      // has decoded yet, assume a 20 ms frame (an assumption, not measured).
      buffer.addSilence(
        _lastFrameBytes > 0 ? _lastFrameBytes ~/ 2 : buffer.sampleRate ~/ 50,
      );
    }
  }

  /// Start a fresh timeline (call when a new Deepgram stream starts).
  void resetStream() {
    buffer.reset();
    _lastFrameBytes = 0;
    session.startNewStream();
  }

  // --- Embedding ---------------------------------------------------------

  /// Voice vector for [samples] (mono, 16 kHz, floats in [-1, 1]); null if the
  /// model is not ready or the clip is too short for the model.
  Float32List? embed(Float32List samples) {
    final extractor = _extractor;
    if (extractor == null || samples.isEmpty) return null;
    final stream = extractor.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: buffer.sampleRate);
      stream.inputFinished();
      if (!extractor.isReady(stream)) return null;
      final e = extractor.compute(stream);
      return e.isEmpty ? null : e;
    } catch (e) {
      debugPrint('Speaker embedding failed: $e');
      return null;
    } finally {
      stream.free();
    }
  }

  // --- People ------------------------------------------------------------

  /// Replace the enrolled voices (call after load / enroll / rename / delete).
  void setProfiles(List<SpeakerProfile> profiles) {
    matcher.profiles = profiles;
    session.refreshProfiles(profiles);
  }

  /// Apply a changed threshold from settings.
  void updateThreshold(double value) => matcher.threshold = value;

  void dispose() {
    _disposed = true;
    _extractor?.free();
    _extractor = null;
    _initFuture = null;
  }
}
