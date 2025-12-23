import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/main.dart';

void main() {
  testWidgets('Cmd+C / Cmd+V copies and pastes selected clip', (tester) async {
    // Ignore overflow errors in test environment (layout depends on platform fonts).
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final container = ProviderContainer();
    var containerDisposed = false;
    addTearDown(() {
      if (!containerDisposed) container.dispose();
    });

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VideoEditorApp(),
      ),
    );
    await tester.pumpAndSettle();

    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);
    final clip = Clip(
      id: 'c1',
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    timeline = timeline.addClipToTrack(track.id, clip);

    container.read(timelineProvider.notifier).loadTimeline(timeline);
    container.read(selectionProvider.notifier).selectClip(clip.id, track.id);
    container
        .read(timelineProvider.notifier)
        .setCurrentPosition(const Duration(seconds: 3));
    await tester.pump();

    // Cmd+C
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    // Cmd+V
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final updated = container.read(timelineProvider);
    expect(updated.videoTracks.first.clips, hasLength(2));

    final pasted = updated.videoTracks.first.clips.firstWhere(
      (c) => c.id != clip.id,
    );
    expect(pasted.mediaItemId, clip.mediaItemId);
    expect(pasted.sourceStart, clip.sourceStart);
    expect(pasted.sourceDuration, clip.sourceDuration);
    expect(pasted.startTime, const Duration(seconds: 3));
    expect(pasted.endTime, const Duration(seconds: 5));

    final selection = container.read(selectionProvider);
    expect(selection.selectedClipId, pasted.id);
    expect(selection.selectedTrackId, track.id);

    // Ensure timers from providers are canceled before the framework checks invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    containerDisposed = true;
  });
}
