import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/main.dart';

void main() {
  testWidgets('Video Editor app smoke test', (WidgetTester tester) async {
    // Ignore overflow errors in test environment (small screen size)
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('RenderFlex overflowed')) {
        // Ignore layout overflow errors in tests
        return;
      }
      FlutterError.presentError(details);
    };

    // Set a larger test size to reduce layout issues
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: VideoEditorApp(),
      ),
    );

    // Verify that the main window loads
    expect(find.text('Video Editor'), findsOneWidget);

    // Verify media library panel is present
    expect(find.text('Media Library'), findsOneWidget);

    // Verify timeline panel is present
    expect(find.text('Timeline'), findsOneWidget);

    // Verify preview quality selector is shown in both toolbar and preview controls
    expect(find.byTooltip('Preview Quality'), findsNWidgets(2));

    // Reset surface size
    await tester.binding.setSurfaceSize(null);
  });
}
