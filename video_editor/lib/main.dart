import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/screens/main_window.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _appendFatalLog('FlutterError', details.exception, details.stack ?? StackTrace.current);
  };

  runZonedGuarded(() {
    runApp(
      const ProviderScope(
        child: VideoEditorApp(),
      ),
    );
  }, (error, stackTrace) {
    _appendFatalLog('Zone', error, stackTrace);
  });
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

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

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
