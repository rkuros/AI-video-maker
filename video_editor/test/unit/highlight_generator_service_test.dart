import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/beat_analyzer_service.dart';
import 'package:video_editor/core/services/highlight_generator_service.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';

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
}

