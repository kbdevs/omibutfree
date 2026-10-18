import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/services/speaker_matching.dart';

/// Deterministic "voice": a fixed random direction plus small per-clip noise.
Float32List voice(int seed, {double noise = 0.05, int clipSeed = 0, int dim = 64}) {
  final base = math.Random(seed);
  final jitter = math.Random(1000 + clipSeed + seed * 7919);
  final v = Float32List(dim);
  for (int i = 0; i < dim; i++) {
    v[i] = (base.nextDouble() * 2 - 1) + (jitter.nextDouble() * 2 - 1) * noise;
  }
  return v;
}

Uint8List pcm(List<int> samples) {
  final b = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  group('vector helpers', () {
    test('cosine of identical vectors is 1, orthogonal is 0', () {
      final a = Float32List.fromList([1, 0, 0]);
      final b = Float32List.fromList([0, 1, 0]);
      expect(cosineSimilarity(a, a), closeTo(1, 1e-6));
      expect(cosineSimilarity(a, b), closeTo(0, 1e-6));
    });

    test('mismatched or zero vectors give -1 instead of throwing', () {
      expect(cosineSimilarity(Float32List(3), Float32List(4)), -1);
      expect(cosineSimilarity(Float32List(3), Float32List(3)), -1);
    });

    test('centroid is unit length and between its inputs', () {
      final c = centroidOf([
        Float32List.fromList([1, 0]),
        Float32List.fromList([0, 1]),
      ]);
      expect(c[0], closeTo(math.sqrt1_2, 1e-6));
      expect(c[1], closeTo(math.sqrt1_2, 1e-6));
    });
  });

  group('PcmRingBuffer', () {
    test('slice maps stream seconds to the right samples', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 100);
      buf.add(pcm(List.generate(50, (i) => i * 100))); // 5 s of ramp
      final clip = buf.slice(1.0, 2.0)!; // samples 10..19
      expect(clip.length, 10);
      expect(clip.first, closeTo(1000 / 32768, 1e-6));
      expect(clip.last, closeTo(1900 / 32768, 1e-6));
      expect(buf.durationSeconds, 5.0);
    });

    test('returns null for audio that has not arrived yet', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 100);
      buf.add(pcm(List.filled(20, 1)));
      expect(buf.slice(1.0, 3.0), isNull);
    });

    test('returns null for audio that has been overwritten', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 5); // 50 samples
      buf.add(pcm(List.generate(120, (i) => i)));
      expect(buf.slice(0, 2), isNull); // aged out
      final recent = buf.slice(10.0, 12.0)!; // samples 100..119
      expect(recent.first, closeTo(100 / 32768, 1e-6));
      expect(recent.last, closeTo(119 / 32768, 1e-6));
    });

    test('odd-length chunks do not shift the byte alignment', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 100);
      final all = pcm([1000, -2000, 3000, -4000]);
      buf.add(Uint8List.sublistView(all, 0, 3)); // 1.5 samples
      buf.add(Uint8List.sublistView(all, 3, 8));
      final clip = buf.slice(0, 0.4)!;
      expect(clip.map((v) => (v * 32768).round()).toList(),
          [1000, -2000, 3000, -4000]);
    });

    test('reset starts a new timeline', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 100);
      buf.add(pcm(List.filled(30, 5)));
      buf.reset();
      expect(buf.durationSeconds, 0);
      expect(buf.slice(0, 1), isNull);
    });

    test('silence keeps the timeline aligned', () {
      final buf = PcmRingBuffer(sampleRate: 10, capacitySeconds: 100);
      buf.add(pcm(List.filled(10, 100)));
      buf.addSilence(10);
      buf.add(pcm(List.filled(10, 100)));
      expect(buf.durationSeconds, 3.0);
      expect(buf.slice(1.0, 2.0)!.every((v) => v == 0), isTrue);
    });
  });

  group('SpeakerMatcher', () {
    SpeakerProfile profile(String id, int seed, {int clips = 4}) => SpeakerProfile(
          id: id,
          name: id,
          embeddings: [for (int c = 0; c < clips; c++) voice(seed, clipSeed: c)],
        );

    test('identifies the right person from a fresh clip', () {
      final m = SpeakerMatcher(threshold: 0.5)
        ..profiles = [profile('alice', 1), profile('bob', 2), profile('carol', 3)];
      final r = m.match(voice(2, clipSeed: 99));
      expect(r.profile?.id, 'bob');
      expect(r.score, greaterThan(0.9));
    });

    test('rejects an unknown voice', () {
      final m = SpeakerMatcher(threshold: 0.5)
        ..profiles = [profile('alice', 1), profile('bob', 2)];
      final r = m.match(voice(777, clipSeed: 5));
      expect(r.profile, isNull);
    });

    test('rejects an ambiguous voice that sits between two people', () {
      // Sum of two *unit* vectors is exactly equidistant from both (a raw sum
      // is not: random vectors differ in length, tilting it toward one).
      final a = l2Normalize(voice(1, noise: 0));
      final b = l2Normalize(voice(2, noise: 0));
      final mix = Float32List(a.length);
      for (int i = 0; i < mix.length; i++) {
        mix[i] = a[i] + b[i];
      }
      final m = SpeakerMatcher(threshold: 0.3)
        ..profiles = [
          SpeakerProfile(id: 'a', name: 'a', embeddings: [a]),
          SpeakerProfile(id: 'b', name: 'b', embeddings: [b]),
        ];
      final r = m.match(mix);
      expect(r.profile, isNull, reason: 'margin check should reject near-ties');
    });

    test('ignores embeddings from a model with a different size', () {
      final m = SpeakerMatcher(threshold: 0.5)
        ..profiles = [
          SpeakerProfile(id: 'old', name: 'old', embeddings: [voice(1, dim: 32)]),
        ];
      expect(m.match(voice(1, dim: 64)).profile, isNull);
    });

    test('profile with no embeddings never matches', () {
      final m = SpeakerMatcher()
        ..profiles = [SpeakerProfile(id: 'x', name: 'x', embeddings: [])];
      expect(m.match(voice(1)).profile, isNull);
    });
  });

  group('SpeakerSession', () {
    SpeakerSession session() {
      final m = SpeakerMatcher(threshold: 0.5)
        ..profiles = [
          SpeakerProfile(id: 'alice', name: 'Alice',
              embeddings: [for (int c = 0; c < 4; c++) voice(1, clipSeed: c)]),
          SpeakerProfile(id: 'bob', name: 'Bob',
              embeddings: [for (int c = 0; c < 4; c++) voice(2, clipSeed: c)]),
        ];
      return SpeakerSession(matcher: m);
    }

    test('resolves speaker numbers to people', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.addEmbedding(1, voice(2, clipSeed: 51));
      s.resolve(0);
      s.resolve(1);
      expect(s.resolvedFor(0)?.name, 'Alice');
      expect(s.resolvedFor(1)?.name, 'Bob');
    });

    test('keeps the name across a conversation boundary', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.resolve(0);
      s.startNewConversation();
      expect(s.snapshotEmbeddings(), isEmpty);
      expect(s.resolvedFor(0)?.name, 'Alice');
    });

    test('one odd clip does not wipe a known name, repeated misses do', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.resolve(0);
      s.startNewConversation();
      s.addEmbedding(0, voice(900, clipSeed: 1)); // unknown voice, 1 clip
      s.resolve(0);
      expect(s.resolvedFor(0)?.name, 'Alice');
      s.addEmbedding(0, voice(900, clipSeed: 2));
      s.addEmbedding(0, voice(900, clipSeed: 3));
      s.resolve(0);
      expect(s.resolvedFor(0), isNull);
    });

    test('snapshot is a copy and respects the per-speaker cap', () {
      final m = SpeakerMatcher();
      final s = SpeakerSession(matcher: m, maxEmbeddingsPerSpeaker: 3);
      for (int i = 0; i < 5; i++) {
        s.addEmbedding(0, voice(1, clipSeed: i));
      }
      final snap = s.snapshotEmbeddings();
      expect(snap[0]!.length, 3);
      final first = snap[0]!.first;
      // Later changes to the session must not reach the snapshot.
      s.addEmbedding(0, voice(1, clipSeed: 99));
      expect(snap[0]!.length, 3);
      expect(identical(snap[0]!.first, first), isTrue);
      s.startNewConversation();
      expect(snap[0]!.length, 3, reason: 'snapshot survives the reset');
    });

    test('startNewStream forgets both embeddings and resolved names', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.resolve(0);
      expect(s.resolvedFor(0)?.name, 'Alice');
      s.startNewStream();
      expect(s.resolvedFor(0), isNull);
      expect(s.snapshotEmbeddings(), isEmpty);
    });

    test('forgetPerson clears resolutions for a deleted person', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.resolve(0);
      s.forgetPerson('alice');
      expect(s.resolvedFor(0), isNull);
    });

    test('forgetPerson also drops the samples of the speakers it named', () {
      final s = session();
      s.addEmbedding(0, voice(1, clipSeed: 50));
      s.addEmbedding(1, voice(2, clipSeed: 60));
      s.resolve(0);
      s.forgetPerson('alice');
      expect(s.snapshotEmbeddings().containsKey(0), isFalse);
      expect(s.snapshotEmbeddings().containsKey(1), isTrue);
    });
  });
}
