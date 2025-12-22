import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'timeline.dart';
import 'media_item.dart';
import 'export_settings.dart';

part 'project.g.dart';

const _uuid = Uuid();

/// Represents a complete video editing project
@JsonSerializable()
class Project {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Timeline timeline;
  final List<MediaItem> mediaLibrary;
  final ExportSettings defaultExportSettings;

  /// Maximum timeline duration (optional, for UI display)
  /// If null, timeline can grow indefinitely
  final Duration? maxDuration;

  Project({
    String? id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Timeline? timeline,
    List<MediaItem>? mediaLibrary,
    ExportSettings? defaultExportSettings,
    this.maxDuration,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        timeline = timeline ?? Timeline(),
        mediaLibrary = mediaLibrary ?? [],
        defaultExportSettings = defaultExportSettings ?? ExportSettings();

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  Project copyWith({
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    Timeline? timeline,
    List<MediaItem>? mediaLibrary,
    ExportSettings? defaultExportSettings,
    Duration? maxDuration,
    bool clearMaxDuration = false,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timeline: timeline ?? this.timeline,
      mediaLibrary: mediaLibrary ?? List.from(this.mediaLibrary),
      defaultExportSettings:
          defaultExportSettings ?? this.defaultExportSettings,
      maxDuration: clearMaxDuration ? null : (maxDuration ?? this.maxDuration),
    );
  }

  /// Update the project with a new updated timestamp
  Project touch() {
    return copyWith(updatedAt: DateTime.now());
  }

  /// Add a media item to the library
  Project addMediaItem(MediaItem item) {
    return copyWith(
      mediaLibrary: [...mediaLibrary, item],
    ).touch();
  }

  /// Remove a media item from the library
  Project removeMediaItem(String itemId) {
    return copyWith(
      mediaLibrary: mediaLibrary.where((i) => i.id != itemId).toList(),
    ).touch();
  }

  /// Get a media item by ID
  MediaItem? getMediaItem(String itemId) {
    try {
      return mediaLibrary.firstWhere((i) => i.id == itemId);
    } catch (_) {
      return null;
    }
  }

  /// Update the timeline
  Project updateTimeline(Timeline timeline) {
    return copyWith(timeline: timeline).touch();
  }
}
