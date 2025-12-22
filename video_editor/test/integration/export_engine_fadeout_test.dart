import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:video_editor/core/engines/export_engine.dart';
import 'package:video_editor/core/models/models.dart';

bool _hasTool(String tool) {
  try {
    final result = Process.runSync(tool, const ['-version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> _runChecked(String exe, List<String> args) async {
  final result = await Process.run(exe, args);
  if (result.exitCode != 0) {
    throw Exception(
      '$exe failed (${result.exitCode})\n\nstdout:\n${result.stdout}\n\nstderr:\n${result.stderr}',
    );
  }
}

Future<double> _probeDurationSeconds(String filePath) async {
  final result = await Process.run('ffprobe', [
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'default=noprint_wrappers=1:nokey=1',
    filePath,
  ]);
  if (result.exitCode != 0) {
    throw Exception('ffprobe failed: ${result.stderr ?? result.stdout}');
  }
  return double.tryParse((result.stdout as String).trim()) ?? 0.0;
}

void main() {
  final ffmpegAvailable = _hasTool('ffmpeg') && _hasTool('ffprobe');

  test(
    'ExportEngine applies fadeOut without halving duration',
    () async {
      if (!ffmpegAvailable) return;

      final tempDir =
          await Directory.systemTemp.createTemp('export_engine_fadeout_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final clipPath = path.join(tempDir.path, 'clip.mp4');
      final outPath = path.join(tempDir.path, 'out.mp4');

      await _runChecked('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=red:s=320x240:d=2:r=30',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        clipPath,
      ]);

      final item = MediaItem(
        name: 'clip',
        filePath: clipPath,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );

      final track = Track(type: TrackType.video, name: 'V1');
      var timeline = Timeline().addTrack(track);

      final clip = Clip(
        mediaItemId: item.id,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        sourceStart: Duration.zero,
        sourceDuration: const Duration(seconds: 2),
        outTransition: TransitionEffect(
          name: TransitionType.fadeOut.name,
          duration: const Duration(milliseconds: 1500),
          type: TransitionType.fadeOut,
        ),
      );

      timeline = timeline.addClipToTrack(track.id, clip);

      final engine = ExportEngine();
      await engine.exportTimeline(
        timeline,
        [item],
        ExportSettings(
          outputPath: outPath,
          format: VideoFormat.mp4,
          resolution: Resolution.r720p,
          quality: Quality.standard,
          frameRate: 30,
        ),
        (_) {},
      );

      expect(await File(outPath).exists(), isTrue);
      expect(await File(outPath).length(), greaterThan(0));

      // Duration should still be close to 2s (fade should not shorten timeline).
      final duration = await _probeDurationSeconds(outPath);
      expect(duration, greaterThan(1.8));
      expect(duration, lessThan(2.2));
    },
    skip: !ffmpegAvailable,
  );
}

