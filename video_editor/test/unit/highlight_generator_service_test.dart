import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/beat_analyzer_service.dart';
import 'package:video_editor/core/services/highlight_generator_service.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';

class _FakeBeatAnalyzerService extends BeatAnalyzerService {
  _FakeBeatAnalyzerService() : super(FFmpegVideoEngine());

  @override
  Future<BeatAnalysisResult> analyzeBeat(String audioFilePath) async {
    return BeatAnalysisResult(
      bpm: 120,
      totalDuration: const Duration(seconds: 30),
      beats: [
        BeatMarker(
          timestamp: const Duration(milliseconds: 200),
          intensity: 1,
          type: BeatType.strong,
        ),
        BeatMarker(
          timestamp: const Duration(milliseconds: 400),
          intensity: 1,
          type: BeatType.accent,
        ),
        BeatMarker(
          timestamp: const Duration(milliseconds: 600),
          intensity: 1,
          type: BeatType.strong,
        ),
        BeatMarker(
          timestamp: const Duration(seconds: 6),
          intensity: 1,
          type: BeatType.accent,
        ),
      ],
    );
  }
}

void main() {
  test('Time-based highlight keeps mediaItemId and source offsets', () async {
    final baseTrack = Track(type: TrackType.video, name: 'V1');
    var base = Timeline().addTrack(baseTrack);

    final clip1 = Clip(
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 6),
      sourceStart: const Duration(seconds: 10),
      sourceDuration: const Duration(seconds: 6),
    );
    final clip2 = Clip(
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 6),
      endTime: const Duration(seconds: 12),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 6),
    );
    base = base.addClipToTrack(baseTrack.id, clip1);
    base = base.addClipToTrack(baseTrack.id, clip2);

    final service = HighlightGeneratorService(
      BeatAnalyzerService(FFmpegVideoEngine()),
      [], // Empty media library for test
    );
    final highlight = await service.generateTimeBasedHighlight(
      base,
      const Duration(seconds: 6),
    );

    expect(highlight.videoTracks.length, 1);
    final outTrack = highlight.videoTracks.first;
    expect(outTrack.clips, isNotEmpty);

    final allowedMediaIds = {'m1', 'm2'};
    for (final clip in outTrack.clips) {
      expect(allowedMediaIds.contains(clip.mediaItemId), isTrue);
      expect(clip.sourceDuration, clip.duration);
      expect(clip.sourceDuration, greaterThan(Duration.zero));
    }

    final ordered = List<Clip>.from(outTrack.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i].startTime, ordered[i - 1].endTime);
    }
  });

  test(
    'Time-based highlight can require at least one segment per clip',
    () async {
      final baseTrack = Track(type: TrackType.video, name: 'V1');
      var base = Timeline().addTrack(baseTrack);

      base = base.addClipToTrack(
        baseTrack.id,
        Clip(
          mediaItemId: 'm1',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 6),
          sourceStart: Duration.zero,
          sourceDuration: const Duration(seconds: 6),
        ),
      );
      base = base.addClipToTrack(
        baseTrack.id,
        Clip(
          mediaItemId: 'm2',
          startTime: const Duration(seconds: 6),
          endTime: const Duration(seconds: 12),
          sourceStart: Duration.zero,
          sourceDuration: const Duration(seconds: 6),
        ),
      );
      base = base.addClipToTrack(
        baseTrack.id,
        Clip(
          mediaItemId: 'm3',
          startTime: const Duration(seconds: 12),
          endTime: const Duration(seconds: 18),
          sourceStart: Duration.zero,
          sourceDuration: const Duration(seconds: 6),
        ),
      );

      final service = HighlightGeneratorService(
        BeatAnalyzerService(FFmpegVideoEngine()),
        [],
      );
      final highlight = await service.generateTimeBasedHighlight(
        base,
        const Duration(seconds: 3),
        preferences: const HighlightPreferences(requireAllClips: true),
      );

      final outTrack = highlight.videoTracks.single;
      final outMediaIds = outTrack.clips.map((c) => c.mediaItemId).toSet();
      expect(outMediaIds, containsAll(<String>['m1', 'm2', 'm3']));
      expect(
        outTrack.clips.fold(Duration.zero, (acc, c) => acc + c.duration),
        const Duration(seconds: 3),
      );
    },
  );

  test('Requiring all clips fails when target duration is too short', () async {
    final baseTrack = Track(type: TrackType.video, name: 'V1');
    var base = Timeline().addTrack(baseTrack);

    for (var i = 0; i < 4; i++) {
      base = base.addClipToTrack(
        baseTrack.id,
        Clip(
          mediaItemId: 'm$i',
          startTime: Duration(seconds: i * 6),
          endTime: Duration(seconds: (i + 1) * 6),
          sourceStart: Duration.zero,
          sourceDuration: const Duration(seconds: 6),
        ),
      );
    }

    final service = HighlightGeneratorService(
      BeatAnalyzerService(FFmpegVideoEngine()),
      [],
    );

    expect(
      () => service.generateTimeBasedHighlight(
        base,
        const Duration(seconds: 3),
        preferences: const HighlightPreferences(requireAllClips: true),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'Beat-based highlight does not reuse the exact same segment repeatedly',
    () async {
      final baseTrack = Track(type: TrackType.video, name: 'V1');
      var base = Timeline().addTrack(baseTrack);

      base = base.addClipToTrack(
        baseTrack.id,
        Clip(
          mediaItemId: 'm1',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 12),
          sourceStart: Duration.zero,
          sourceDuration: const Duration(seconds: 12),
        ),
      );

      final service = HighlightGeneratorService(
        _FakeBeatAnalyzerService(),
        [],
      );

      final bgm = MediaItem(
        name: 'bgm',
        filePath: '/dev/null',
        type: MediaType.audio,
        duration: const Duration(seconds: 30),
      );

      final highlight = await service.generateBeatBasedHighlight(
        base,
        bgm,
        const Duration(seconds: 8),
        pattern: const HighlightPattern(
          id: 't',
          name: 't',
          weights: {'visual': 0.3, 'audio': 0.3, 'text': 0.4},
          minGapSeconds: 0,
          diversityWeight: 0,
        ),
        preferences: const HighlightPreferences(
          requireAllClips: true,
          minGapSeconds: 0,
          diversityWeight: 0,
        ),
      );

      final outTrack = highlight.videoTracks.single;
      expect(outTrack.clips, isNotEmpty);

      final seenKeys = <String>{};
      for (final c in outTrack.clips) {
        final key =
            '${c.mediaItemId}:${c.sourceStart.inMilliseconds}:${c.sourceDuration.inMilliseconds}';
        expect(seenKeys.add(key), isTrue);
      }
    },
  );
}
