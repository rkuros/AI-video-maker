import 'package:video_editor/core/models/models.dart';

/// Service for managing timeline operations
class TimelineService {
  Timeline _timeline = Timeline();

  Timeline get timeline => _timeline;

  void setTimeline(Timeline timeline) {
    _timeline = timeline;
  }

  /// Add a track to the timeline
  void addTrack(TrackType type, {String? name}) {
    final track = Track(
      type: type,
      name: name ?? 'Track ${_timeline.tracks.length + 1}',
    );
    _timeline = _timeline.addTrack(track);
  }

  /// Remove a track
  void removeTrack(String trackId) {
    _timeline = _timeline.removeTrack(trackId);
  }

  /// Add a clip to a track
  void addClip(String trackId, Clip clip) {
    _timeline = _timeline.addClipToTrack(trackId, clip);
  }

  /// Remove a clip
  void removeClip(String trackId, String clipId) {
    _timeline = _timeline.removeClipFromTrack(trackId, clipId);
  }

  /// Update a clip
  void updateClip(String trackId, Clip clip) {
    _timeline = _timeline.updateClipInTrack(trackId, clip);
  }

  /// Move a clip to a new position
  void moveClip(String clipId, Duration newStartTime) {
    _timeline = _timeline.moveClip(clipId, newStartTime);
  }

  /// Trim a clip
  void trimClip(String clipId, Duration newStart, Duration newEnd) {
    _timeline = _timeline.trimClip(clipId, newStart, newEnd);
  }

  /// Split a clip at a position
  void splitClip(String clipId, Duration position) {
    _timeline = _timeline.splitClip(clipId, position);
  }

  /// Set current playback position
  void setCurrentPosition(Duration position) {
    _timeline = _timeline.copyWith(currentPosition: position);
  }

  /// Clear the timeline
  void clear() {
    _timeline = Timeline();
  }
}
