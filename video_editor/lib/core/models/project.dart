import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'timeline.dart';
import 'timeline_group.dart';
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
  final List<TimelineGroup> timelineGroups;
  final String? activeTimelineGroupId;
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
    List<TimelineGroup>? timelineGroups,
    this.activeTimelineGroupId,
    List<MediaItem>? mediaLibrary,
    ExportSettings? defaultExportSettings,
    this.maxDuration,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        timelineGroups = timelineGroups ?? [TimelineGroup(name: 'Default')],
        mediaLibrary = mediaLibrary ?? [],
        defaultExportSettings = defaultExportSettings ?? ExportSettings();

  factory Project.fromJson(Map<String, dynamic> json) {
    // Migration: Convert old single timeline format to timeline groups
    if (json.containsKey('timeline') && !json.containsKey('timelineGroups')) {
      final oldTimeline = Timeline.fromJson(json['timeline'] as Map<String, dynamic>);
      final defaultGroup = TimelineGroup(
        name: 'Default',
        timeline: oldTimeline,
      );
      json['timelineGroups'] = [defaultGroup.toJson()];
      json['activeTimelineGroupId'] = defaultGroup.id;
      json.remove('timeline');
    }

    // Ensure activeTimelineGroupId is set if not present
    if (json.containsKey('timelineGroups') &&
        !json.containsKey('activeTimelineGroupId')) {
      final groups = (json['timelineGroups'] as List)
          .map((g) => TimelineGroup.fromJson(g as Map<String, dynamic>))
          .toList();
      if (groups.isNotEmpty) {
        json['activeTimelineGroupId'] = groups.first.id;
      }
    }

    return _$ProjectFromJson(json);
  }

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  Project copyWith({
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<TimelineGroup>? timelineGroups,
    String? activeTimelineGroupId,
    List<MediaItem>? mediaLibrary,
    ExportSettings? defaultExportSettings,
    Duration? maxDuration,
    bool clearMaxDuration = false,
    bool clearActiveTimelineGroupId = false,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timelineGroups: timelineGroups ?? List.from(this.timelineGroups),
      activeTimelineGroupId: clearActiveTimelineGroupId
          ? null
          : (activeTimelineGroupId ?? this.activeTimelineGroupId),
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

  /// Get the active timeline group
  TimelineGroup? getActiveGroup() {
    if (activeTimelineGroupId == null) {
      return timelineGroups.isNotEmpty ? timelineGroups.first : null;
    }
    try {
      return timelineGroups.firstWhere((g) => g.id == activeTimelineGroupId);
    } catch (_) {
      return timelineGroups.isNotEmpty ? timelineGroups.first : null;
    }
  }

  /// Get a timeline group by ID
  TimelineGroup? getGroup(String groupId) {
    try {
      return timelineGroups.firstWhere((g) => g.id == groupId);
    } catch (_) {
      return null;
    }
  }

  /// Update a timeline group
  Project updateGroup(TimelineGroup group) {
    final updatedGroups = timelineGroups
        .map((g) => g.id == group.id ? group : g)
        .toList();
    return copyWith(timelineGroups: updatedGroups).touch();
  }

  /// Add a timeline group
  Project addGroup(TimelineGroup group) {
    return copyWith(timelineGroups: [...timelineGroups, group]).touch();
  }

  /// Remove a timeline group
  Project removeGroup(String groupId) {
    final updatedGroups =
        timelineGroups.where((g) => g.id != groupId).toList();

    // If removing the active group, switch to first available group
    String? newActiveId = activeTimelineGroupId;
    if (activeTimelineGroupId == groupId && updatedGroups.isNotEmpty) {
      newActiveId = updatedGroups.first.id;
    }

    return copyWith(
      timelineGroups: updatedGroups,
      activeTimelineGroupId: newActiveId,
    ).touch();
  }

  /// Set the active timeline group
  Project setActiveGroup(String groupId) {
    return copyWith(activeTimelineGroupId: groupId).touch();
  }
}
