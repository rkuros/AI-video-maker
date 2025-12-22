import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/timeline_service.dart';
import 'package:video_editor/core/logic/preview_provider.dart';

/// Provider for timeline service
final timelineServiceProvider = Provider<TimelineService>((ref) {
  return TimelineService();
});

/// State notifier for timeline
class TimelineNotifier extends StateNotifier<Timeline> {
  final TimelineService _service;
  final Ref _ref;

  TimelineNotifier(this._service, this._ref) : super(Timeline());

  static const int _historyLimit = 100;
  final List<Timeline> _undoStack = <Timeline>[];
  final List<Timeline> _redoStack = <Timeline>[];

  /// Invalidate preview when timeline is modified
  void _invalidatePreview() {
    _ref.read(previewProvider.notifier).invalidateTimelinePreview();
  }

  void _recordHistory() {
    _undoStack.add(state);
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _applyMutation(
    void Function() mutate, {
    bool invalidatePreview = true,
    bool recordHistory = true,
  }) {
    if (recordHistory) {
      _recordHistory();
    }
    mutate();
    state = _service.timeline;
    if (invalidatePreview) {
      _invalidatePreview();
    }
  }

  /// Undo the last timeline edit.
  bool undo() {
    if (_undoStack.isEmpty) return false;
    final previous = _undoStack.removeLast();
    _redoStack.add(state);
    _service.setTimeline(previous);
    state = _service.timeline;
    _invalidatePreview();
    return true;
  }

  /// Redo the last undone timeline edit.
  bool redo() {
    if (_redoStack.isEmpty) return false;
    final next = _redoStack.removeLast();
    _undoStack.add(state);
    _service.setTimeline(next);
    state = _service.timeline;
    _invalidatePreview();
    return true;
  }

  /// Add a track
  void addTrack(TrackType type, {String? name}) {
    _applyMutation(() => _service.addTrack(type, name: name));
  }

  /// Remove a track
  void removeTrack(String trackId) {
    _applyMutation(() => _service.removeTrack(trackId));
  }

  /// Add a clip to a track
  void addClip(String trackId, Clip clip) {
    _applyMutation(() => _service.addClip(trackId, clip));
  }

  /// Remove a clip
  void removeClip(String trackId, String clipId) {
    _applyMutation(() => _service.removeClip(trackId, clipId));
  }

  /// Update a clip
  void updateClip(String trackId, Clip clip) {
    _applyMutation(() => _service.updateClip(trackId, clip));
  }

  /// Update a track
  void updateTrack(Track track) {
    _applyMutation(() {
      final timeline = _service.timeline;
      final updatedTimeline = timeline.updateTrack(track);
      _service.setTimeline(updatedTimeline);
    });
  }

  /// Move a clip
  void moveClip(String clipId, Duration newStartTime) {
    _applyMutation(() => _service.moveClip(clipId, newStartTime));
  }

  /// Trim a clip
  void trimClip(String clipId, Duration newStart, Duration newEnd) {
    _applyMutation(() => _service.trimClip(clipId, newStart, newEnd));
  }

  /// Split a clip
  void splitClip(String clipId, Duration position) {
    _applyMutation(() => _service.splitClip(clipId, position));
  }

  /// Set current position
  void setCurrentPosition(Duration position) {
    _applyMutation(
      () => _service.setCurrentPosition(position),
      invalidatePreview: false,
      recordHistory: false,
    );
  }

  /// Load a timeline
  void loadTimeline(Timeline timeline) {
    _undoStack.clear();
    _redoStack.clear();
    _service.setTimeline(timeline);
    state = _service.timeline;
    _invalidatePreview();
  }

  /// Clear timeline
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _service.clear();
    state = _service.timeline;
    _invalidatePreview();
  }

  /// Add an effect to a clip
  void addEffect(String clipId, Effect effect) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: [...clip.effects, effect],
    );
    updateClip(track.id, updatedClip);
    // Note: updateClip already calls _invalidatePreview()
  }

  /// Remove an effect from a clip
  void removeEffect(String clipId, String effectId) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: clip.effects.where((e) => e.id != effectId).toList(),
    );
    updateClip(track.id, updatedClip);
    // Note: updateClip already calls _invalidatePreview()
  }

  /// Update an effect on a clip
  void updateEffect(String clipId, Effect effect) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: clip.effects.map((e) => e.id == effect.id ? effect : e).toList(),
    );
    updateClip(track.id, updatedClip);
    // Note: updateClip already calls _invalidatePreview()
  }
}

/// Provider for timeline state
final timelineProvider =
    StateNotifierProvider<TimelineNotifier, Timeline>((ref) {
  final service = ref.watch(timelineServiceProvider);
  return TimelineNotifier(service, ref);
});

/// Provider for current playback position
final currentPositionProvider = Provider<Duration>((ref) {
  final timeline = ref.watch(timelineProvider);
  return timeline.currentPosition;
});

/// Provider for timeline duration
final timelineDurationProvider = Provider<Duration>((ref) {
  final timeline = ref.watch(timelineProvider);
  return timeline.duration;
});

/// Provider for video tracks
final videoTracksProvider = Provider<List<Track>>((ref) {
  final timeline = ref.watch(timelineProvider);
  return timeline.videoTracks;
});

/// Provider for audio tracks
final audioTracksProvider = Provider<List<Track>>((ref) {
  final timeline = ref.watch(timelineProvider);
  return timeline.audioTracks;
});
