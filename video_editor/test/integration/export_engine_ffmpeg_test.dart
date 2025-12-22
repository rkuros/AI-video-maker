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

void main() {
  final ffmpegAvailable = _hasTool('ffmpeg') && _hasTool('ffprobe');

  test(
    'ExportEngine exports a simple 2-clip timeline (with xfade)',
    () async {
      if (!ffmpegAvailable) return;

      final tempDir =
          await Directory.systemTemp.createTemp('export_engine_ffmpeg_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final clip1Path = path.join(tempDir.path, 'clip1.mp4');
      final clip2Path = path.join(tempDir.path, 'clip2.mp4');
      final outPath = path.join(tempDir.path, 'out.mp4');

      // clip1: 2s red video + sine audio
      await _runChecked('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=red:s=320x240:d=2',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=1000:duration=2',
        '-shortest',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '96k',
        clip1Path,
      ]);

      // clip2: 2s blue video (no audio)
      await _runChecked('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=blue:s=320x240:d=2',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        clip2Path,
      ]);

      final item1 = MediaItem(
        name: 'clip1',
        filePath: clip1Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );
      final item2 = MediaItem(
        name: 'clip2',
        filePath: clip2Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );

      final track = Track(type: TrackType.video, name: 'V1');
      var timeline = Timeline().addTrack(track);

      final clip1 = Clip(
        mediaItemId: item1.id,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        sourceStart: Duration.zero,
        sourceDuration: const Duration(seconds: 2),
      );
      final clip2 = Clip(
        mediaItemId: item2.id,
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

      final engine = ExportEngine();
      await engine.exportTimeline(
        timeline,
        [item1, item2],
        ExportSettings(
          outputPath: outPath,
          format: VideoFormat.mp4,
          resolution: Resolution.r720p,
          quality: Quality.standard,
          frameRate: 30,
        ),
        (_) {},
      );

      final outFile = File(outPath);
      expect(await outFile.exists(), isTrue);
      expect(await outFile.length(), greaterThan(0));
    },
    skip: !ffmpegAvailable,
  );

  test(
    'ExportEngine exports an overlapped 2-clip timeline (xfade path)',
    () async {
      if (!ffmpegAvailable) return;

      final tempDir =
          await Directory.systemTemp.createTemp('export_engine_ffmpeg_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final clip1Path = path.join(tempDir.path, 'clip1.mp4');
      final clip2Path = path.join(tempDir.path, 'clip2.mp4');
      final outPath = path.join(tempDir.path, 'out_xfade.mp4');

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
        clip1Path,
      ]);

      await _runChecked('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=blue:s=320x240:d=2:r=30',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        clip2Path,
      ]);

      final item1 = MediaItem(
        name: 'clip1',
        filePath: clip1Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );
      final item2 = MediaItem(
        name: 'clip2',
        filePath: clip2Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );

      final track = Track(type: TrackType.video, name: 'V1');
      var timeline = Timeline().addTrack(track);

      final clip1 = Clip(
        mediaItemId: item1.id,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        sourceStart: Duration.zero,
        sourceDuration: const Duration(seconds: 2),
      );
      final clip2 = Clip(
        mediaItemId: item2.id,
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(milliseconds: 3500),
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

      final engine = ExportEngine();
      await engine.exportTimeline(
        timeline,
        [item1, item2],
        ExportSettings(
          outputPath: outPath,
          format: VideoFormat.mp4,
          resolution: Resolution.r720p,
          quality: Quality.standard,
          frameRate: 30,
        ),
        (_) {},
      );

      final outFile = File(outPath);
      expect(await outFile.exists(), isTrue);
      expect(await outFile.length(), greaterThan(0));
    },
    skip: !ffmpegAvailable,
  );

  test(
    'ExportEngine exports zoom out transition without unsupported xfade names',
    () async {
      if (!ffmpegAvailable) return;

      final tempDir =
          await Directory.systemTemp.createTemp('export_engine_ffmpeg_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final clip1Path = path.join(tempDir.path, 'clip1.mp4');
      final clip2Path = path.join(tempDir.path, 'clip2.mp4');
      final outPath = path.join(tempDir.path, 'out_zoom_out.mp4');

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
        clip1Path,
      ]);

      await _runChecked('ffmpeg', [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=blue:s=320x240:d=2:r=30',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        clip2Path,
      ]);

      final item1 = MediaItem(
        name: 'clip1',
        filePath: clip1Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );
      final item2 = MediaItem(
        name: 'clip2',
        filePath: clip2Path,
        type: MediaType.video,
        duration: const Duration(seconds: 2),
      );

      final track = Track(type: TrackType.video, name: 'V1');
      var timeline = Timeline().addTrack(track);

      final clip1 = Clip(
        mediaItemId: item1.id,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 2),
        sourceStart: Duration.zero,
        sourceDuration: const Duration(seconds: 2),
      );
      final clip2 = Clip(
        mediaItemId: item2.id,
        startTime: const Duration(milliseconds: 1500),
        endTime: const Duration(milliseconds: 3500),
        sourceStart: Duration.zero,
        sourceDuration: const Duration(seconds: 2),
        inTransition: TransitionEffect(
          name: TransitionType.zoom.name,
          duration: const Duration(milliseconds: 500),
          type: TransitionType.zoom,
          parameters: const {'zoomType': 'out'},
        ),
      );

      timeline = timeline.addClipToTrack(track.id, clip1);
      timeline = timeline.addClipToTrack(track.id, clip2);

      final engine = ExportEngine();
      await engine.exportTimeline(
        timeline,
        [item1, item2],
        ExportSettings(
          outputPath: outPath,
          format: VideoFormat.mp4,
          resolution: Resolution.r720p,
          quality: Quality.standard,
          frameRate: 30,
        ),
        (_) {},
      );

      final outFile = File(outPath);
      expect(await outFile.exists(), isTrue);
      expect(await outFile.length(), greaterThan(0));
    },
    skip: !ffmpegAvailable,
  );
}
