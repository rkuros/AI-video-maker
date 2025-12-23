import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_editor/core/services/highlight_feature_cache.dart';
import 'ui/screens/main_window.dart';

void main() {
  MediaKit.ensureInitialized();
  HighlightFeatureCache.installExitHandlers();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _appendFatalLog(
      'FlutterError',
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };

  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: VideoEditorApp()));
    },
    (error, stackTrace) {
      _appendFatalLog('Zone', error, stackTrace);
    },
  );
}

void _appendFatalLog(String source, Object error, StackTrace stackTrace) {
  try {
    final now = DateTime.now().toIso8601String();
    final logPath = '${Directory.systemTemp.path}/video_editor_fatal.log';
    File(logPath).writeAsStringSync(
      '[$now][$source] $error\n$stackTrace\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Ignore logging failures to avoid recursive crashes.
  }
}

class VideoEditorApp extends StatefulWidget {
  const VideoEditorApp({super.key});

  @override
  State<VideoEditorApp> createState() => _VideoEditorAppState();
}

class _VideoEditorAppState extends State<VideoEditorApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(HighlightFeatureCache.instance.clear());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(HighlightFeatureCache.instance.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainWindow(),
      debugShowCheckedModeBanner: false,
    );
  }
}
