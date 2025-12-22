import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:video_editor/core/engines/video_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/media_library_service.dart';

void main() {
  group('MediaLibraryService.hydrateItem', () {
    late Directory tempDir;
    late MediaLibraryService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hydrate_test');
      service = MediaLibraryService(_FakeVideoEngine());
    });

    tearDown(() async {
      service.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('hydrates video metadata and thumbnail while preserving id', () async {
      final filePath = path.join(tempDir.path, 'a.mp4');
      await File(filePath).writeAsString('stub');

      final original = MediaItem(
        id: 'fixed-id',
        name: 'a.mp4',
        filePath: filePath,
        type: MediaType.video,
        duration: Duration.zero,
      );

      final hydrated = await service.hydrateItem(original);

      expect(hydrated.id, 'fixed-id');
      expect(hydrated.videoInfo, isNotNull);
      expect(hydrated.duration, const Duration(seconds: 12));
      expect(hydrated.thumbnail, isNotNull);
      expect(hydrated.thumbnail, isNotEmpty);
    });

    test('returns input unchanged when file is missing', () async {
      final original = MediaItem(
        id: 'fixed-id',
        name: 'missing.mp4',
        filePath: path.join(tempDir.path, 'missing.mp4'),
        type: MediaType.video,
        duration: Duration.zero,
      );

      final hydrated = await service.hydrateItem(original);

      expect(identical(hydrated, original), isTrue);
    });

    test('hydrates audio duration while preserving id', () async {
      final filePath = path.join(tempDir.path, 'a.mp3');
      await File(filePath).writeAsString('stub');

      final original = MediaItem(
        id: 'fixed-id',
        name: 'a.mp3',
        filePath: filePath,
        type: MediaType.audio,
        duration: Duration.zero,
      );

      final hydrated = await service.hydrateItem(original);

      expect(hydrated.id, 'fixed-id');
      expect(hydrated.audioInfo, isNotNull);
      expect(hydrated.duration, const Duration(seconds: 7));
    });
  });
}

class _FakeVideoEngine implements VideoEngine {
  @override
  Future<void> loadVideo(String filePath) async {}

  @override
  Future<VideoInfo> getVideoInfo(String filePath) async {
    return VideoInfo(
      resolution: Resolution.r1080p,
      frameRate: 30,
      duration: const Duration(seconds: 12),
      codec: 'h264',
      bitrate: 0,
    );
  }

  @override
  Future<AudioInfo> getAudioInfo(String filePath) async {
    return AudioInfo(
      sampleRate: 44100,
      channels: 2,
      duration: const Duration(seconds: 7),
      codec: 'aac',
      bitrate: 0,
    );
  }

  @override
  Future<Uint8List> generateThumbnail(
    String filePath,
    Duration timestamp, {
    int width = 320,
    int height = 180,
  }) async {
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> applyEffect(String inputPath, String outputPath, Effect effect) async {}

  @override
  Future<void> applyDenoise(
    String inputPath,
    String outputPath,
    DenoiseSettings settings,
  ) async {}

  @override
  Future<List<double>> extractWaveform(
    String audioPath, {
    int sampleCount = 1000,
  }) async {
    return List.filled(sampleCount, 0.0);
  }

  @override
  Future<void> dispose() async {}
}

