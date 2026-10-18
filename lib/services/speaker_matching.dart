// Pure-Dart building blocks for speaker recognition.
//
// Nothing in this file touches native code, so it is easy to unit test:
//  * [PcmRingBuffer]   – rolling window of the live PCM stream, addressable by
//                        stream time (the same clock Deepgram's word
//                        timestamps use).
//  * [SpeakerMatcher]  – cosine-similarity matching of a voice embedding
//                        against enrolled people.
//  * [SpeakerSession]  – tracks the embeddings collected for each Deepgram
//                        "speaker N" and decides which enrolled person (if
//                        any) that speaker is.
import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Vector helpers
// ---------------------------------------------------------------------------

double _dot(Float32List a, Float32List b) {
  double s = 0;
  for (int i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// Returns a unit-length copy of [v] (or [v] unchanged if it is all zeros).
Float32List l2Normalize(Float32List v) {
  final norm = math.sqrt(_dot(v, v));
  if (norm == 0) return Float32List.fromList(v);
  final out = Float32List(v.length);
  for (int i = 0; i < v.length; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}

/// Cosine similarity of two vectors of equal length, in [-1, 1].
double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length || a.isEmpty) return -1;
  final na = math.sqrt(_dot(a, a));
  final nb = math.sqrt(_dot(b, b));
  if (na == 0 || nb == 0) return -1;
  return _dot(a, b) / (na * nb);
}

/// Mean of the (normalized) embeddings, re-normalized. All inputs must have
/// the same length.
Float32List centroidOf(List<Float32List> embeddings) {
  assert(embeddings.isNotEmpty);
  final dim = embeddings.first.length;
  final sum = Float32List(dim);
  for (final e in embeddings) {
    final n = l2Normalize(e);
    for (int i = 0; i < dim; i++) {
      sum[i] += n[i];
    }
  }
  return l2Normalize(sum);
}

// ---------------------------------------------------------------------------
// PCM ring buffer
// ---------------------------------------------------------------------------

/// Keeps the most recent [capacitySeconds] of 16-bit little-endian mono PCM and
/// lets callers cut out a clip by stream time.
///
/// Stream time 0 is the moment [reset] was last called, which must coincide
/// with the first audio byte sent to the speech-to-text service.
class PcmRingBuffer {
  PcmRingBuffer({this.sampleRate = 16000, int capacitySeconds = 300})
      : _capacity = sampleRate * capacitySeconds,
        _samples = Int16List(sampleRate * capacitySeconds);

  final int sampleRate;
  final int _capacity;
  final Int16List _samples;

  /// Total samples written since the last [reset].
  int _total = 0;
  int? _carryByte; // dangling low byte when a chunk had an odd length

  /// Seconds of audio received since the last [reset].
  double get durationSeconds => _total / sampleRate;

  void reset() {
    _total = 0;
    _carryByte = null;
  }

  /// Append raw PCM16 little-endian bytes.
  void add(Uint8List bytes) {
    int i = 0;
    if (_carryByte != null && bytes.isNotEmpty) {
      _push(_toInt16(_carryByte!, bytes[0]));
      _carryByte = null;
      i = 1;
    }
    while (i + 1 < bytes.length) {
      _push(_toInt16(bytes[i], bytes[i + 1]));
      i += 2;
    }
    if (i < bytes.length) _carryByte = bytes[i];
  }

  /// Append [sampleCount] samples of silence (used to keep the timeline aligned
  /// when an audio frame could not be decoded).
  void addSilence(int sampleCount) {
    for (int i = 0; i < sampleCount; i++) {
      _push(0);
    }
  }

  static int _toInt16(int lo, int hi) {
    final v = (hi << 8) | lo;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  void _push(int sample) {
    _samples[_total % _capacity] = sample;
    _total++;
  }

  /// Returns the audio between [startSec] and [endSec] as floats in [-1, 1], or
  /// null if that range has not arrived yet or has already been overwritten.
  Float32List? slice(double startSec, double endSec) {
    int start = (startSec * sampleRate).round();
    int end = (endSec * sampleRate).round();
    if (start < 0) start = 0;
    if (end > _total) return null; // not received yet
    if (end <= start) return null;
    if (start < _total - _capacity) return null; // aged out
    final out = Float32List(end - start);
    for (int i = 0; i < out.length; i++) {
      out[i] = _samples[(start + i) % _capacity] / 32768.0;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// An enrolled person and the voice embeddings we have collected for them.
class SpeakerProfile {
  SpeakerProfile({
    required this.id,
    required this.name,
    required List<Float32List> embeddings,
  }) : embeddings = embeddings.map(l2Normalize).toList();

  final String id;
  String name;
  final List<Float32List> embeddings;
}

class MatchResult {
  const MatchResult({this.profile, required this.score, required this.runnerUp});

  /// The matched person, or null when nobody scored high enough.
  final SpeakerProfile? profile;

  /// Similarity of the best candidate (even if it was rejected).
  final double score;

  /// Similarity of the second-best person (-1 if there is only one).
  final double runnerUp;
}

class SpeakerMatcher {
  SpeakerMatcher({this.threshold = 0.6, this.margin = 0.05, this.topK = 3});

  /// Minimum similarity to accept a match.
  double threshold;

  /// The best person must beat the runner-up by at least this much, otherwise
  /// the voice is considered ambiguous.
  final double margin;

  /// A person's score is the mean of their [topK] best embedding similarities.
  final int topK;

  List<SpeakerProfile> profiles = [];

  double _personScore(SpeakerProfile p, Float32List q) {
    final sims = <double>[];
    for (final e in p.embeddings) {
      if (e.length != q.length) continue; // enrolled with a different model
      sims.add(cosineSimilarity(e, q));
    }
    if (sims.isEmpty) return -1;
    sims.sort((a, b) => b.compareTo(a));
    final k = math.min(topK, sims.length);
    double sum = 0;
    for (int i = 0; i < k; i++) {
      sum += sims[i];
    }
    return sum / k;
  }

  MatchResult match(Float32List query) {
    SpeakerProfile? best;
    double bestScore = -1;
    double second = -1;
    for (final p in profiles) {
      final s = _personScore(p, query);
      if (s > bestScore) {
        second = bestScore;
        bestScore = s;
        best = p;
      } else if (s > second) {
        second = s;
      }
    }
    if (best == null || bestScore < threshold || bestScore - second < margin) {
      return MatchResult(score: bestScore, runnerUp: second);
    }
    return MatchResult(profile: best, score: bestScore, runnerUp: second);
  }
}

// ---------------------------------------------------------------------------
// Per-session speaker tracking
// ---------------------------------------------------------------------------

/// Tracks voice embeddings per Deepgram speaker index.
///
/// Deepgram's "speaker 0 / 1 / 2" numbers are only meaningful inside one
/// streaming session, so everything here is keyed by that number and lives for
/// one listening session. Embeddings are cleared at each conversation
/// boundary (they are saved with the conversation first) but the
/// speaker→person resolution is carried over so a speaker keeps their name
/// when a new conversation starts.
class SpeakerSession {
  SpeakerSession({required this.matcher, this.maxEmbeddingsPerSpeaker = 12});

  final SpeakerMatcher matcher;
  final int maxEmbeddingsPerSpeaker;

  final Map<int, List<Float32List>> _embeddings = {};
  final Map<int, SpeakerProfile> _resolved = {};

  /// Minimum clips before we are willing to drop a previously-resolved name
  /// because the latest clips no longer match anyone.
  static const int _clearAfter = 3;

  /// Record an embedding for [speakerId]. Oldest clips are dropped past the cap.
  void addEmbedding(int speakerId, Float32List embedding) {
    final list = _embeddings.putIfAbsent(speakerId, () => []);
    list.add(embedding);
    if (list.length > maxEmbeddingsPerSpeaker) list.removeAt(0);
  }

  /// The person currently believed to be [speakerId], or null.
  SpeakerProfile? resolvedFor(int speakerId) => _resolved[speakerId];

  /// Re-evaluate [speakerId] from the embeddings gathered so far and return the
  /// match for those clips. A match is remembered for [resolvedFor]. When the
  /// clips match nobody, the returned `profile` is null but [resolvedFor] keeps
  /// the earlier name until at least [_clearAfter] clips have failed to match,
  /// so one noisy clip does not drop a name. Use [resolvedFor] for the name to
  /// show.
  MatchResult? resolve(int speakerId) {
    final embs = _embeddings[speakerId];
    if (embs == null || embs.isEmpty) return null;
    final result = matcher.match(centroidOf(embs));
    if (result.profile != null) {
      _resolved[speakerId] = result.profile!;
    } else if (embs.length >= _clearAfter) {
      _resolved.remove(speakerId);
    }
    return result;
  }

  /// Copy of the embeddings collected for the current conversation.
  Map<int, List<Float32List>> snapshotEmbeddings() => {
        for (final e in _embeddings.entries) e.key: List.of(e.value),
      };

  /// Call when a new conversation starts: forget embeddings, keep names.
  void startNewConversation() => _embeddings.clear();

  /// Call when Deepgram starts a new stream (e.g. after a reconnect): its
  /// "speaker N" numbers start over, so neither the collected embeddings nor
  /// the names resolved from them still apply.
  void startNewStream() {
    _embeddings.clear();
    _resolved.clear();
  }

  /// Drop everything tied to a person (e.g. they were deleted): the name, and
  /// the voice samples collected for the speakers that were resolved to them.
  void forgetPerson(String personId) {
    final speakers = [
      for (final e in _resolved.entries)
        if (e.value.id == personId) e.key,
    ];
    for (final k in speakers) {
      _resolved.remove(k);
      _embeddings.remove(k);
    }
  }

  /// After people were enrolled/renamed, point resolutions at fresh profiles.
  void refreshProfiles(List<SpeakerProfile> profiles) {
    final byId = {for (final p in profiles) p.id: p};
    final stale = <int>[];
    for (final e in _resolved.entries) {
      final fresh = byId[e.value.id];
      if (fresh == null) {
        stale.add(e.key);
      } else {
        _resolved[e.key] = fresh;
      }
    }
    for (final k in stale) {
      _resolved.remove(k);
    }
  }
}
