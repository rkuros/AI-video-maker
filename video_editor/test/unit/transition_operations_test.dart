import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/transition_provider.dart';
import 'package:video_editor/core/models/models.dart';

void main() {
  test('Applying an xfade transition creates overlap on the timeline', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    final clip1 = Clip(
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    final clip2 = Clip(
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 2),
      endTime: const Duration(seconds: 4),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);
    container.read(timelineProvider.notifier).loadTimeline(timeline);

    container.read(transitionSettingsProvider.notifier).setType(
          TransitionType.crossFade,
        );
    container.read(transitionSettingsProvider.notifier).setDuration(
          const Duration(milliseconds: 500),
        );

    final ops = container.read(transitionOperationsProvider);
    ops.applyInTransition(track.id, clip2.id);

    final updated = container.read(timelineProvider);
    final updatedTrack = updated.getTrack(track.id)!;
    final updatedClips = List<Clip>.from(updatedTrack.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    expect(updatedClips.length, 2);
    expect(updatedClips[0].id, clip1.id);
    expect(updatedClips[1].id, clip2.id);
    expect(updatedClips[1].startTime, const Duration(milliseconds: 1500));
    expect(updatedClips[1].inTransition?.type, TransitionType.crossFade);
  });
}

