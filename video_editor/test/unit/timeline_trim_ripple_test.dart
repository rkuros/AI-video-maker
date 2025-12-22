import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/models/models.dart';

void main() {
  test('Trimming clip end ripples later clips to avoid overlap', () {
    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    final clip1 = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    final clip2 = Clip(
      id: 'c2',
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 2),
      endTime: const Duration(seconds: 4),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);

    // Extend clip1 by +1s: clip2 should be pushed right.
    final trimmed = timeline.trimClip(
      clip1.id,
      Duration.zero,
      const Duration(seconds: 3),
    );

    final t = trimmed.getTrack(track.id)!;
    final updated2 = t.getClip(clip2.id)!;
    expect(updated2.startTime, const Duration(seconds: 3));
    expect(updated2.endTime, const Duration(seconds: 5));
  });

  test('Trimming clip end preserves allowed overlap for xfade transitions', () {
    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    final clip1 = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    final clip2 = Clip(
      id: 'c2',
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 2),
      endTime: const Duration(seconds: 4),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
      inTransition: TransitionEffect(
        name: TransitionType.crossFade.name,
        duration: const Duration(milliseconds: 500),
        type: TransitionType.crossFade,
      ),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);

    // Extend clip1 into clip2 by 300ms: should not push (overlap is allowed).
    final trimmedA = timeline.trimClip(
      clip1.id,
      Duration.zero,
      const Duration(milliseconds: 2300),
    );
    final a2 = trimmedA.getTrack(track.id)!.getClip(clip2.id)!;
    expect(a2.startTime, const Duration(seconds: 2));

    // Extend clip1 by 800ms: allow 500ms overlap, so clip2 should be pushed by 300ms.
    final trimmedB = timeline.trimClip(
      clip1.id,
      Duration.zero,
      const Duration(milliseconds: 2800),
    );
    final b2 = trimmedB.getTrack(track.id)!.getClip(clip2.id)!;
    expect(b2.startTime, const Duration(milliseconds: 2300));
  });

  test('Trimming start earlier without handle does not extend the end', () {
    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    // Clip has no left handle (sourceStart == 0).
    final clip1 = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: const Duration(seconds: 5),
      endTime: const Duration(seconds: 7),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    final clip2 = Clip(
      id: 'c2',
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 7),
      endTime: const Duration(seconds: 9),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);

    // Attempt to extend left by 1s (5s -> 4s) while keeping end at 7s.
    final trimmed = timeline.trimClip(
      clip1.id,
      const Duration(seconds: 4),
      const Duration(seconds: 7),
    );

    final t = trimmed.getTrack(track.id)!;
    final updated1 = t.getClip(clip1.id)!;
    expect(updated1.startTime, const Duration(seconds: 5));
    expect(updated1.endTime, const Duration(seconds: 7));
    expect(updated1.sourceStart, Duration.zero);
    expect(updated1.sourceDuration, const Duration(seconds: 2));
  });

  test('Trimming start earlier clamps against previous clip overlap', () {
    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    final clip1 = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    // Give clip2 a left handle (sourceStart>0) so it can be extended left.
    final clip2 = Clip(
      id: 'c2',
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 2),
      endTime: const Duration(seconds: 4),
      sourceStart: const Duration(seconds: 1),
      sourceDuration: const Duration(seconds: 2),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);

    // Attempt to extend clip2 into clip1 by 1s. No transition => no overlap allowed.
    final trimmed = timeline.trimClip(
      clip2.id,
      const Duration(seconds: 1),
      const Duration(seconds: 4),
    );

    final updated2 = trimmed.getTrack(track.id)!.getClip(clip2.id)!;
    expect(updated2.startTime, const Duration(seconds: 2));
    expect(updated2.endTime, const Duration(seconds: 4));
    expect(updated2.sourceStart, const Duration(seconds: 1));
    expect(updated2.sourceDuration, const Duration(seconds: 2));
  });

  test('Trimming start earlier allows bounded overlap for xfade transitions', () {
    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);

    final clip1 = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    final clip2 = Clip(
      id: 'c2',
      mediaItemId: 'm2',
      startTime: const Duration(seconds: 2),
      endTime: const Duration(seconds: 4),
      sourceStart: const Duration(seconds: 1),
      sourceDuration: const Duration(seconds: 2),
      inTransition: TransitionEffect(
        name: TransitionType.crossFade.name,
        duration: const Duration(milliseconds: 500),
        type: TransitionType.crossFade,
      ),
    );

    timeline = timeline.addClipToTrack(track.id, clip1);
    timeline = timeline.addClipToTrack(track.id, clip2);

    // Extend clip2 by 1s; only 500ms overlap allowed, so start clamps to 1.5s.
    final trimmed = timeline.trimClip(
      clip2.id,
      const Duration(seconds: 1),
      const Duration(seconds: 4),
    );

    final updated2 = trimmed.getTrack(track.id)!.getClip(clip2.id)!;
    expect(updated2.startTime, const Duration(milliseconds: 1500));
    expect(updated2.endTime, const Duration(seconds: 4));
    expect(updated2.sourceStart, const Duration(milliseconds: 500));
    expect(updated2.sourceDuration, const Duration(milliseconds: 2500));
  });
}
