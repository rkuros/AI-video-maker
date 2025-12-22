import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/main.dart';

void main() {
  testWidgets('Timeline clip can be trimmed from left/right handles', (tester) async {
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

    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VideoEditorApp(),
      ),
    );
    await tester.pumpAndSettle();

    final item = MediaItem(
      id: 'm1',
      name: 'clip1',
      filePath: '/tmp/clip1.mp4',
      type: MediaType.video,
      duration: const Duration(seconds: 10),
    );
    container.read(mediaLibraryProvider.notifier).loadItems([item]);

    final track = Track(type: TrackType.video, name: 'V1');
    var timeline = Timeline().addTrack(track);
    final clip = Clip(
      id: 'c1',
      mediaItemId: item.id,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
      sourceStart: Duration.zero,
      sourceDuration: const Duration(seconds: 2),
    );
    timeline = timeline.addClipToTrack(track.id, clip);

    container.read(timelineProvider.notifier).loadTimeline(timeline);
    container.read(selectionProvider.notifier).selectClip(clip.id, track.id);
    await tester.pump();

    // Read the current timeline zoom (pixelsPerSecond) from the Zoom slider so the
    // test doesn't assume a hardcoded value.
    final zoomSlider = tester.widgetList<Slider>(find.byType(Slider)).firstWhere(
          (s) => s.min == 10 && s.max == 200,
        );
    final pixelsPerSecond = zoomSlider.value;

    Duration pxToDeltaMs(double px) =>
        Duration(milliseconds: ((px / pixelsPerSecond) * 1000).round());

    // Drag right handle 50px left.
    await tester.drag(find.byKey(const ValueKey('trim_right_c1')), const Offset(-50, 0));
    await tester.pump();

    final trimmedRight = container.read(timelineProvider).findClip('c1')!;
    final expectedRightDuration = const Duration(seconds: 2) + pxToDeltaMs(-50);
    expect(trimmedRight.duration, expectedRightDuration);
    expect(trimmedRight.sourceDuration, expectedRightDuration);

    // Drag left handle 25px right (keeps end fixed, shortens duration).
    await tester.drag(find.byKey(const ValueKey('trim_left_c1')), const Offset(25, 0));
    await tester.pump();

    final trimmedLeft = container.read(timelineProvider).findClip('c1')!;
    final expectedStart = pxToDeltaMs(25);
    final expectedLeftDuration = expectedRightDuration - expectedStart;
    expect(trimmedLeft.startTime, expectedStart);
    expect(trimmedLeft.duration, expectedLeftDuration);
    expect(trimmedLeft.sourceStart, expectedStart);
    expect(trimmedLeft.sourceDuration, expectedLeftDuration);

    // Ensure timers from providers are canceled before the framework checks invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    containerDisposed = true;
  });
}
