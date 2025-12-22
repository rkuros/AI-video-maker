import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/main.dart';

void main() {
  testWidgets('Delete/backspace removes selected timeline clip', (tester) async {
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
      mediaItemId: 'm1',
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    timeline = timeline.addClipToTrack(track.id, clip);

    container.read(timelineProvider.notifier).loadTimeline(timeline);
    container.read(selectionProvider.notifier).selectClip(clip.id, track.id);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    final updated = container.read(timelineProvider);
    expect(updated.videoTracks.first.clips, isEmpty);
    expect(container.read(selectionProvider).hasSelection, isFalse);

    // Ensure timers from providers are canceled before the framework checks invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    containerDisposed = true;
  });
}
