import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/main.dart';

void main() {
  testWidgets('Timeline clip can be selected by click', (tester) async {
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
    await tester.pump();

    expect(container.read(selectionProvider).hasSelection, isFalse);

    await tester.tap(find.byKey(const ValueKey('clip_hit_c1')));
    await tester.pump();

    final selection = container.read(selectionProvider);
    expect(selection.selectedClipId, 'c1');
    expect(selection.selectedTrackId, track.id);

    // Ensure timers from providers are canceled before the framework checks invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    containerDisposed = true;
  });
}
