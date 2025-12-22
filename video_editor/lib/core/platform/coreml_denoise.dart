import 'dart:io';

import 'package:flutter/services.dart';

class CoreMlDenoise {
  static const MethodChannel _channel =
      MethodChannel('video_editor/coreml_denoise');

  static Future<void> denoiseVideo({
    required String inputPath,
    required String outputPath,
    required Duration sourceStart,
    required Duration duration,
    required String modelPath,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Core ML denoise is only supported on macOS.');
    }

    await _channel.invokeMethod<void>('denoiseVideo', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'startMs': sourceStart.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'modelPath': modelPath,
    });
  }
}

