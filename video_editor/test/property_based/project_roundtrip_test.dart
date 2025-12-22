import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:faker/faker.dart';
import 'package:video_editor/core/models/models.dart';

// Feature: video-editor-app, Property 29: プロジェクト保存・読み込みラウンドトリップ
// 検証: 要件 9.1, 9.2, 9.3, 9.4

void main() {
  group('Property 29: Project Save/Load Roundtrip', () {
    final faker = Faker();
    const iterations = 100;

    test('arbitrary project can be saved and restored with full state',
        () {
      for (int i = 0; i < iterations; i++) {
        // Generate arbitrary project with random data
        final project = _generateRandomProject(faker);

        // Simulate save: serialize to JSON
        final json = project.toJson();
        final jsonString = jsonEncode(json);

        // Simulate load: deserialize from JSON
        final loadedJson = jsonDecode(jsonString) as Map<String, dynamic>;
        final loadedProject = Project.fromJson(loadedJson);

        // Verify project properties are preserved
        expect(loadedProject.id, equals(project.id),
            reason: 'Project ID should be preserved');
        expect(loadedProject.name, equals(project.name),
            reason: 'Project name should be preserved');
        expect(loadedProject.createdAt, equals(project.createdAt),
            reason: 'Created timestamp should be preserved');
        expect(loadedProject.updatedAt, equals(project.updatedAt),
            reason: 'Updated timestamp should be preserved');

        // Verify media library is preserved
        expect(loadedProject.mediaLibrary.length,
            equals(project.mediaLibrary.length),
            reason: 'Media library size should be preserved');

        for (int j = 0; j < project.mediaLibrary.length; j++) {
          final original = project.mediaLibrary[j];
          final loaded = loadedProject.mediaLibrary[j];
          expect(loaded.id, equals(original.id),
              reason: 'Media item ID should be preserved');
          expect(loaded.name, equals(original.name),
              reason: 'Media item name should be preserved');
          expect(loaded.filePath, equals(original.filePath),
              reason: 'Media item file path should be preserved');
          expect(loaded.type, equals(original.type),
              reason: 'Media item type should be preserved');
        }

        // Verify timeline structure is preserved
        expect(loadedProject.timeline.id, equals(project.timeline.id),
            reason: 'Timeline ID should be preserved');
        expect(loadedProject.timeline.tracks.length,
            equals(project.timeline.tracks.length),
            reason: 'Timeline track count should be preserved');

        // Verify tracks and clips are preserved
        for (int j = 0; j < project.timeline.tracks.length; j++) {
          final originalTrack = project.timeline.tracks[j];
          final loadedTrack = loadedProject.timeline.tracks[j];

          expect(loadedTrack.id, equals(originalTrack.id),
              reason: 'Track ID should be preserved');
          expect(loadedTrack.type, equals(originalTrack.type),
              reason: 'Track type should be preserved');
          expect(loadedTrack.clips.length, equals(originalTrack.clips.length),
              reason: 'Track clip count should be preserved');

          // Verify clips in track
          for (int k = 0; k < originalTrack.clips.length; k++) {
            final originalClip = originalTrack.clips[k];
            final loadedClip = loadedTrack.clips[k];

            expect(loadedClip.id, equals(originalClip.id),
                reason: 'Clip ID should be preserved');
            expect(loadedClip.mediaItemId, equals(originalClip.mediaItemId),
                reason: 'Clip media item reference should be preserved');
            expect(loadedClip.startTime, equals(originalClip.startTime),
                reason: 'Clip start time should be preserved');
            expect(loadedClip.endTime, equals(originalClip.endTime),
                reason: 'Clip end time should be preserved');

            // Verify effects are preserved
            expect(loadedClip.effects.length,
                equals(originalClip.effects.length),
                reason: 'Clip effect count should be preserved');

            for (int m = 0; m < originalClip.effects.length; m++) {
              final originalEffect = originalClip.effects[m];
              final loadedEffect = loadedClip.effects[m];

              expect(loadedEffect.id, equals(originalEffect.id),
                  reason: 'Effect ID should be preserved');
              expect(loadedEffect.type, equals(originalEffect.type),
                  reason: 'Effect type should be preserved');
              expect(loadedEffect.name, equals(originalEffect.name),
                  reason: 'Effect name should be preserved');
            }
          }
        }

        // Verify export settings are preserved
        expect(loadedProject.defaultExportSettings.format,
            equals(project.defaultExportSettings.format),
            reason: 'Export format should be preserved');
        expect(loadedProject.defaultExportSettings.resolution,
            equals(project.defaultExportSettings.resolution),
            reason: 'Export resolution should be preserved');
        expect(loadedProject.defaultExportSettings.quality,
            equals(project.defaultExportSettings.quality),
            reason: 'Export quality should be preserved');
      }
    });
  });
}

/// Generate a random project for property-based testing
Project _generateRandomProject(Faker faker) {
  final mediaItemCount = faker.randomGenerator.integer(10, min: 0);
  final trackCount = faker.randomGenerator.integer(5, min: 1);

  // Generate random media items
  final mediaItems = List.generate(
    mediaItemCount,
    (index) => MediaItem(
      name: faker.lorem.word(),
      filePath: '/path/to/${faker.lorem.word()}.mp4',
      type: _randomMediaType(faker),
      duration: Duration(
        seconds: faker.randomGenerator.integer(600, min: 1),
      ),
    ),
  );

  // Generate random tracks with clips
  final tracks = List.generate(
    trackCount,
    (index) {
      final trackType =
          index % 2 == 0 ? TrackType.video : TrackType.audio;
      final clipCount = faker.randomGenerator.integer(5, min: 0);

      final clips = mediaItems.isEmpty
          ? <Clip>[]
          : List.generate(
              clipCount,
              (clipIndex) {
                final startSec =
                    faker.randomGenerator.integer(1000, min: 0);
                final durationSec =
                    faker.randomGenerator.integer(60, min: 1);

                return Clip(
                  mediaItemId: mediaItems[faker.randomGenerator
                          .integer(mediaItems.length)]
                      .id,
                  startTime: Duration(seconds: startSec),
                  endTime:
                      Duration(seconds: startSec + durationSec),
                  sourceStart: Duration.zero,
                  sourceDuration: Duration(seconds: durationSec),
                  effects: _generateRandomEffects(faker),
                  volume: faker.randomGenerator.decimal(),
                  isMuted: faker.randomGenerator.boolean(),
                );
              },
            );

      return Track(
        type: trackType,
        name: '${trackType.name} Track ${index + 1}',
        clips: clips,
        volume: faker.randomGenerator.decimal(),
        isMuted: faker.randomGenerator.boolean(),
        isLocked: faker.randomGenerator.boolean(),
      );
    },
  );

  final timeline = Timeline(
    tracks: tracks,
    currentPosition: Duration(
      seconds: faker.randomGenerator.integer(100, min: 0),
    ),
  );

  final exportSettings = ExportSettings(
    format: _randomVideoFormat(faker),
    resolution: _randomResolution(faker),
    quality: _randomQuality(faker),
    frameRate: [24, 30, 60][faker.randomGenerator.integer(3)],
  );

  return Project(
    name: faker.lorem.sentence(),
    createdAt: faker.date.dateTime(minYear: 2020, maxYear: 2024),
    updatedAt: faker.date.dateTime(minYear: 2020, maxYear: 2024),
    timeline: timeline,
    mediaLibrary: mediaItems,
    defaultExportSettings: exportSettings,
  );
}

MediaType _randomMediaType(Faker faker) {
  final types = MediaType.values;
  return types[faker.randomGenerator.integer(types.length)];
}

VideoFormat _randomVideoFormat(Faker faker) {
  final formats = VideoFormat.values;
  return formats[faker.randomGenerator.integer(formats.length)];
}

Resolution _randomResolution(Faker faker) {
  final resolutions = Resolution.values;
  return resolutions[faker.randomGenerator.integer(resolutions.length)];
}

Quality _randomQuality(Faker faker) {
  final qualities = Quality.values;
  return qualities[faker.randomGenerator.integer(qualities.length)];
}

List<Effect> _generateRandomEffects(Faker faker) {
  final effectCount = faker.randomGenerator.integer(3, min: 0);
  return List.generate(
    effectCount,
    (index) => Effect(
      name: 'Effect ${index + 1}',
      type: 'test_effect',
      parameters: {
        'intensity': faker.randomGenerator.decimal(),
        'param1': faker.randomGenerator.integer(100),
      },
    ),
  );
}
