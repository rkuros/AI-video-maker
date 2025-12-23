import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'clip.dart';
import 'enums.dart';

part 'track.g.dart';

const _uuid = Uuid();

/// Represents a track on the timeline (video or audio)
@JsonSerializable()
class Track {
  final String id;
  final TrackType type;
  final List<Clip> clips;
  final bool isLocked;
  final bool isMuted;
  final bool isVisible;
  final String name;
  final double volume; // 0.0 to 1.0

  Track({
    String? id,
    required this.type,
    List<Clip>? clips,
    this.isLocked = false,
    this.isMuted = false,
    this.isVisible = true,
    String? name,
    this.volume = 1.0,
  })  : id = id ?? _uuid.v4(),
        clips = clips ?? [],
        name = name ?? 'Track ${type.name}';

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);

  Map<String, dynamic> toJson() => _$TrackToJson(this);

  /// Get the total duration of the track (end time of the last clip)
  Duration get duration {
    if (clips.isEmpty) return Duration.zero;
    return clips.map((c) => c.endTime).reduce((a, b) => a > b ? a : b);
  }

  Track copyWith({
    TrackType? type,
    List<Clip>? clips,
    bool? isLocked,
    bool? isMuted,
    bool? isVisible,
    String? name,
    double? volume,
  }) {
    return Track(
      id: id,
      type: type ?? this.type,
      clips: clips ?? List.from(this.clips),
      isLocked: isLocked ?? this.isLocked,
      isMuted: isMuted ?? this.isMuted,
      isVisible: isVisible ?? this.isVisible,
      name: name ?? this.name,
      volume: volume ?? this.volume,
    );
  }

  /// Add a clip to the track
  Track addClip(Clip clip) {
    final newClips = [...clips, clip];
    newClips.sort((a, b) => a.startTime.compareTo(b.startTime));
    return copyWith(clips: newClips);
  }

  /// Remove a clip from the track
  Track removeClip(String clipId) {
    return copyWith(
      clips: clips.where((c) => c.id != clipId).toList(),
    );
  }

  /// Update a clip in the track
  Track updateClip(Clip clip) {
    final newClips = clips.map((c) => c.id == clip.id ? clip : c).toList();
    newClips.sort((a, b) => a.startTime.compareTo(b.startTime));
    return copyWith(clips: newClips);
  }

  /// Get a clip by ID
  Clip? getClip(String clipId) {
    try {
      return clips.firstWhere((c) => c.id == clipId);
    } catch (_) {
      return null;
    }
  }

  /// Check if a clip overlaps with existing clips
  bool hasOverlap(Clip newClip, {String? excludeClipId}) {
    for (final clip in clips) {
      if (excludeClipId != null && clip.id == excludeClipId) continue;

      final overlapStart = clip.startTime.inMicroseconds <
              newClip.endTime.inMicroseconds &&
          clip.endTime.inMicroseconds > newClip.startTime.inMicroseconds;

      if (overlapStart) return true;
    }
    return false;
  }
}
