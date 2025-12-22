import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:faker/faker.dart';
import 'package:video_editor/core/engines/video_engine.dart';
import 'package:video_editor/core/services/media_library_service.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/utils/file_validator.dart';
import 'package:path/path.dart' as path;

// Feature: video-editor-app
// Property 1: ファイルインポート一貫性
// Property 2: 非対応ファイル拒否
// 検証: 要件 1.1, 1.2, 1.3, 1.4, 1.5

void main() {
  group('Property 1: File Import Consistency', () {
    late MediaLibraryService service;
    late Directory tempDir;
    final faker = Faker();
    const iterations = 100;

    setUp(() async {
      service = MediaLibraryService(_FakeVideoEngine());
      tempDir = await Directory.systemTemp.createTemp('media_library_test');
    });

    tearDown(() async {
      service.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'any valid media file (MP4, MOV, AVI, MKV, MP3, WAV, AAC, JPEG, PNG) '
        'can be imported via drag & drop and added to Media_Library',
        () async {
      for (int i = 0; i < iterations; i++) {
        // Generate random supported file
        final extension = _randomSupportedExtension(faker);
        final fileName = '${faker.lorem.word()}$extension';
        final filePath = path.join(tempDir.path, fileName);

        // Create actual file
        final file = File(filePath);
        await file.writeAsString('test content');

        // Import file
        final mediaItem = await service.importFile(filePath);

        // Verify file was added to library
        expect(service.items, contains(mediaItem),
            reason: 'Imported file should be in media library');

        // Verify media item properties
        expect(mediaItem.filePath, equals(filePath),
            reason: 'File path should be preserved');
        expect(mediaItem.name, equals(fileName),
            reason: 'File name should be preserved');

        // Verify media type is correctly identified
        final expectedType = FileValidator.getMediaType(filePath);
        expect(mediaItem.type, equals(expectedType),
            reason: 'Media type should match file extension');

        // Verify we can retrieve the item
        final retrieved = service.getItem(mediaItem.id);
        expect(retrieved, isNotNull,
            reason: 'Should be able to retrieve imported item');
        expect(retrieved!.id, equals(mediaItem.id),
            reason: 'Retrieved item should have same ID');

        // Clean up for next iteration
        await file.delete();
        service.clear();
      }
    });

    test('multiple files can be imported simultaneously', () async {
      for (int i = 0; i < 20; i++) {
        final fileCount = faker.randomGenerator.integer(10, min: 1);
        final filePaths = <String>[];

        // Create multiple test files
        for (int j = 0; j < fileCount; j++) {
          final extension = _randomSupportedExtension(faker);
          final fileName = '${faker.lorem.word()}_$j$extension';
          final filePath = path.join(tempDir.path, fileName);

          final file = File(filePath);
          await file.writeAsString('test content $j');
          filePaths.add(filePath);
        }

        // Import all files
        final importedItems = await service.importFiles(filePaths);

        // Verify all files were imported
        expect(importedItems.length, equals(fileCount),
            reason: 'All valid files should be imported');
        expect(service.items.length, equals(fileCount),
            reason: 'Library should contain all imported files');

        // Clean up
        for (final filePath in filePaths) {
          await File(filePath).delete();
        }
        service.clear();
      }
    });

    test('imported files can be filtered by media type', () async {
      final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];
      final audioExtensions = ['.mp3', '.wav', '.aac'];
      final imageExtensions = ['.jpg', '.png'];

      var videoCount = 0;
      var audioCount = 0;
      var imageCount = 0;

      // Create one of each type
      for (final ext in videoExtensions) {
        final filePath = path.join(tempDir.path, 'video$videoCount$ext');
        await File(filePath).writeAsString('video');
        await service.importFile(filePath);
        videoCount++;
      }

      for (final ext in audioExtensions) {
        final filePath = path.join(tempDir.path, 'audio$audioCount$ext');
        await File(filePath).writeAsString('audio');
        await service.importFile(filePath);
        audioCount++;
      }

      for (final ext in imageExtensions) {
        final filePath = path.join(tempDir.path, 'image$imageCount$ext');
        await File(filePath).writeAsString('image');
        await service.importFile(filePath);
        imageCount++;
      }

      // Verify filtering
      final videos = service.getItems(filter: MediaType.video);
      final audios = service.getItems(filter: MediaType.audio);
      final images = service.getItems(filter: MediaType.image);

      expect(videos.length, equals(videoCount),
          reason: 'Should retrieve all video files');
      expect(audios.length, equals(audioCount),
          reason: 'Should retrieve all audio files');
      expect(images.length, equals(imageCount),
          reason: 'Should retrieve all image files');

      // Verify all items are of correct type
      expect(videos.every((item) => item.type == MediaType.video), isTrue,
          reason: 'All filtered videos should be video type');
      expect(audios.every((item) => item.type == MediaType.audio), isTrue,
          reason: 'All filtered audios should be audio type');
      expect(images.every((item) => item.type == MediaType.image), isTrue,
          reason: 'All filtered images should be image type');
    });
  });

  group('Property 2: Unsupported File Rejection', () {
    late MediaLibraryService service;
    late Directory tempDir;
    final faker = Faker();
    const iterations = 50;

    setUp(() async {
      service = MediaLibraryService(_FakeVideoEngine());
      tempDir = await Directory.systemTemp.createTemp('media_library_test');
    });

    tearDown(() async {
      service.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'any unsupported file format throws UnsupportedFileFormatException '
        'and is not added to Media_Library', () async {
      for (int i = 0; i < iterations; i++) {
        // Generate random unsupported file
        final extension = _randomUnsupportedExtension(faker);
        final fileName = '${faker.lorem.word()}$extension';
        final filePath = path.join(tempDir.path, fileName);

        // Create actual file
        final file = File(filePath);
        await file.writeAsString('test content');

        final initialCount = service.items.length;

        // Attempt to import unsupported file
        expect(
          () async => await service.importFile(filePath),
          throwsA(isA<UnsupportedFileFormatException>()),
          reason: 'Unsupported file should throw exception',
        );

        // Verify file was NOT added to library
        expect(service.items.length, equals(initialCount),
            reason: 'Unsupported file should not be added to library');

        // Clean up
        await file.delete();
      }
    });

    test('mixed valid and invalid files import only valid ones', () async {
      for (int i = 0; i < 20; i++) {
        final validCount = faker.randomGenerator.integer(5, min: 1);
        final invalidCount = faker.randomGenerator.integer(5, min: 1);
        final filePaths = <String>[];

        // Create valid files
        for (int j = 0; j < validCount; j++) {
          final extension = _randomSupportedExtension(faker);
          final fileName = 'valid_$j$extension';
          final filePath = path.join(tempDir.path, fileName);
          await File(filePath).writeAsString('valid content');
          filePaths.add(filePath);
        }

        // Create invalid files
        for (int j = 0; j < invalidCount; j++) {
          final extension = _randomUnsupportedExtension(faker);
          final fileName = 'invalid_$j$extension';
          final filePath = path.join(tempDir.path, fileName);
          await File(filePath).writeAsString('invalid content');
          filePaths.add(filePath);
        }

        // Import all files
        final importedItems = await service.importFiles(filePaths);

        // Verify only valid files were imported
        expect(importedItems.length, equals(validCount),
            reason: 'Only valid files should be imported');
        expect(service.items.length, equals(validCount),
            reason: 'Library should only contain valid files');

        // Clean up
        for (final filePath in filePaths) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        service.clear();
      }
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
      duration: const Duration(seconds: 10),
      codec: 'h264',
      bitrate: 0,
    );
  }

  @override
  Future<AudioInfo> getAudioInfo(String filePath) async {
    return AudioInfo(
      sampleRate: 44100,
      channels: 2,
      duration: const Duration(seconds: 10),
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
    return Uint8List(0);
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

String _randomSupportedExtension(Faker faker) {
  final extensions = FileValidator.allSupportedExtensions;
  return extensions[faker.randomGenerator.integer(extensions.length)];
}

String _randomUnsupportedExtension(Faker faker) {
  final unsupportedExtensions = [
    '.txt',
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.zip',
    '.rar',
    '.7z',
    '.exe',
    '.dmg',
    '.iso',
    '.webm', // Not supported yet
    '.flac', // Not supported yet
    '.gif', // Not supported yet
  ];
  return unsupportedExtensions[
      faker.randomGenerator.integer(unsupportedExtensions.length)];
}
