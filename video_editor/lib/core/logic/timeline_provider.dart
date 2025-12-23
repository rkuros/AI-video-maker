import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/logic/preview_provider.dart';

/// State notifier for timeline groups
class TimelineNotifier extends StateNotifier<Timeline> {
  final Ref _ref;

  TimelineNotifier(this._ref) : super(Timeline());

  static const int _historyLimit = 100;
  static const int maxGroups = 10;

  // Multi-group state
  List<TimelineGroup> _groups = [TimelineGroup(name: 'Default')];
  String? _activeGroupId;

  // Per-group undo/redo stacks
  final Map<String, List<Timeline>> _undoStacks = {};
  final Map<String, List<Timeline>> _redoStacks = {};

  /// Get all timeline groups
  List<TimelineGroup> getGroups() => List.unmodifiable(_groups);

  /// Get the active group
  TimelineGroup? getActiveGroup() {
    if (_activeGroupId == null && _groups.isNotEmpty) {
      _activeGroupId = _groups.first.id;
    }
    if (_activeGroupId == null) return null;
    try {
      return _groups.firstWhere((g) => g.id == _activeGroupId);
    } catch (_) {
      if (_groups.isNotEmpty) {
        _activeGroupId = _groups.first.id;
        return _groups.first;
      }
      return null;
    }
  }

  /// Get active group ID
  String? get activeGroupId => _activeGroupId ?? (_groups.isNotEmpty ? _groups.first.id : null);

  /// Invalidate preview when timeline is modified
  void _invalidatePreview() {
    _ref.read(previewProvider.notifier).invalidateTimelinePreview();
  }

  void _recordHistory() {
    final groupId = _activeGroupId;
    if (groupId == null) return;

    _undoStacks.putIfAbsent(groupId, () => []);
    _undoStacks[groupId]!.add(state);

    if (_undoStacks[groupId]!.length > _historyLimit) {
      _undoStacks[groupId]!.removeAt(0);
    }

    _redoStacks[groupId] = [];
  }

  void _applyMutation(
    Timeline Function(Timeline) mutate, {
    bool invalidatePreview = true,
    bool recordHistory = true,
  }) {
    final group = getActiveGroup();
    if (group == null) return;

    if (recordHistory) {
      _recordHistory();
    }

    final newTimeline = mutate(group.timeline);
    _updateActiveGroupTimeline(newTimeline);

    if (invalidatePreview) {
      _invalidatePreview();
    }
  }

  void _updateActiveGroupTimeline(Timeline timeline) {
    final group = getActiveGroup();
    if (group == null) return;

    final updatedGroup = group.copyWith(timeline: timeline);
    _groups = _groups.map((g) => g.id == updatedGroup.id ? updatedGroup : g).toList();

    state = timeline;
  }

  /// Undo the last timeline edit for the active group
  bool undo() {
    final groupId = _activeGroupId;
    if (groupId == null || !_undoStacks.containsKey(groupId) || _undoStacks[groupId]!.isEmpty) {
      return false;
    }

    final previous = _undoStacks[groupId]!.removeLast();
    _redoStacks.putIfAbsent(groupId, () => []);
    _redoStacks[groupId]!.add(state);

    _updateActiveGroupTimeline(previous);
    _invalidatePreview();

    return true;
  }

  /// Redo the last undone timeline edit for the active group
  bool redo() {
    final groupId = _activeGroupId;
    if (groupId == null || !_redoStacks.containsKey(groupId) || _redoStacks[groupId]!.isEmpty) {
      return false;
    }

    final next = _redoStacks[groupId]!.removeLast();
    _undoStacks.putIfAbsent(groupId, () => []);
    _undoStacks[groupId]!.add(state);

    _updateActiveGroupTimeline(next);
    _invalidatePreview();

    return true;
  }

  /// Set the active group
  void setActiveGroup(String groupId) {
    final group = _groups.where((g) => g.id == groupId).firstOrNull;
    if (group != null) {
      _activeGroupId = groupId;
      state = group.timeline;
      _invalidatePreview();
    }
  }

  /// Add a new timeline group
  void addGroup(String name) {
    if (_groups.length >= maxGroups) {
      throw Exception('Maximum number of groups ($maxGroups) reached');
    }

    final newGroup = TimelineGroup(name: name);
    _groups = [..._groups, newGroup];
    _activeGroupId = newGroup.id;
    state = newGroup.timeline;
    _invalidatePreview();
  }

  /// Remove a timeline group
  void removeGroup(String groupId) {
    if (_groups.length <= 1) {
      throw Exception('Cannot remove the last group');
    }

    _groups = _groups.where((g) => g.id != groupId).toList();

    // Clear undo/redo stacks for removed group
    _undoStacks.remove(groupId);
    _redoStacks.remove(groupId);

    // If removing active group, switch to first available
    if (_activeGroupId == groupId) {
      if (_groups.isNotEmpty) {
        _activeGroupId = _groups.first.id;
        state = _groups.first.timeline;
      } else {
        _activeGroupId = null;
        state = Timeline();
      }
      _invalidatePreview();
    } else {
      // Force state update to notify listeners even if active group didn't change
      state = state.copyWith();
    }
  }

  /// Rename a timeline group
  void renameGroup(String groupId, String newName) {
    final group = _groups.where((g) => g.id == groupId).firstOrNull;
    if (group != null) {
      final updatedGroup = group.copyWith(name: newName);
      _groups = _groups.map((g) => g.id == groupId ? updatedGroup : g).toList();
      // Force state update by creating a new Timeline instance to notify listeners
      state = state.copyWith();
    }
  }

  /// Load timeline groups (used when loading project)
  void loadGroups(List<TimelineGroup> groups, {String? activeGroupId}) {
    _undoStacks.clear();
    _redoStacks.clear();

    if (groups.isEmpty) {
      _groups = [TimelineGroup(name: 'Default')];
      _activeGroupId = _groups.first.id;
    } else {
      _groups = List.from(groups);
      _activeGroupId = activeGroupId;
    }

    final activeGroup = getActiveGroup();
    state = activeGroup?.timeline ?? Timeline();
    _invalidatePreview();
  }

  /// Add a track to the active group
  void addTrack(TrackType type, {String? name}) {
    _applyMutation((timeline) {
      final track = Track(
        type: type,
        name: name ?? 'Track ${timeline.tracks.length + 1}',
      );
      return timeline.addTrack(track);
    });
  }

  /// Remove a track from the active group
  void removeTrack(String trackId) {
    _applyMutation((timeline) => timeline.removeTrack(trackId));
  }

  /// Add a clip to a track in the active group
  void addClip(String trackId, Clip clip) {
    _applyMutation((timeline) => timeline.addClipToTrack(trackId, clip));
  }

  /// Remove a clip from the active group
  void removeClip(String trackId, String clipId) {
    _applyMutation((timeline) => timeline.removeClipFromTrack(trackId, clipId));
  }

  /// Update a clip in the active group
  void updateClip(String trackId, Clip clip) {
    _applyMutation((timeline) => timeline.updateClipInTrack(trackId, clip));
  }

  /// Update a track in the active group
  void updateTrack(Track track) {
    _applyMutation((timeline) => timeline.updateTrack(track));
  }

  /// Move a clip in the active group
  void moveClip(String clipId, Duration newStartTime) {
    _applyMutation((timeline) => timeline.moveClip(clipId, newStartTime));
  }

  /// Move a clip to a different track in the active group
  void moveClipToTrack(String clipId, String targetTrackId, Duration newStartTime) {
    _applyMutation((timeline) {
      // Find the clip in the current track
      Track? sourceTrack;
      Clip? clipToMove;

      for (final track in timeline.tracks) {
        final clip = track.clips.where((c) => c.id == clipId).firstOrNull;
        if (clip != null) {
          sourceTrack = track;
          clipToMove = clip;
          break;
        }
      }

      if (sourceTrack == null || clipToMove == null) return timeline;
      if (sourceTrack.id == targetTrackId) {
        // Same track, just move position
        return timeline.moveClip(clipId, newStartTime);
      }

      // Remove from source track
      var updatedTimeline = timeline.removeClipFromTrack(sourceTrack.id, clipId);

      // Add to target track with new start time
      final newClip = clipToMove.copyWith(
        startTime: newStartTime,
        endTime: newStartTime + clipToMove.duration,
      );
      updatedTimeline = updatedTimeline.addClipToTrack(targetTrackId, newClip);

      return updatedTimeline;
    });
  }

  /// Trim a clip in the active group
  void trimClip(String clipId, Duration newStart, Duration newEnd) {
    _applyMutation((timeline) => timeline.trimClip(clipId, newStart, newEnd));
  }

  /// Split a clip in the active group
  void splitClip(String clipId, Duration position) {
    _applyMutation((timeline) => timeline.splitClip(clipId, position));
  }

  /// Set current position in the active group
  void setCurrentPosition(Duration position) {
    _applyMutation(
      (timeline) => timeline.copyWith(currentPosition: position),
      invalidatePreview: false,
      recordHistory: false,
    );
  }

  /// Load a timeline (replace active group's timeline, clear undo/redo)
  void loadTimeline(Timeline timeline) {
    final group = getActiveGroup();
    if (group == null) return;

    final groupId = group.id;

    // Clear undo/redo for this group
    _undoStacks[groupId] = [];
    _redoStacks[groupId] = [];

    _updateActiveGroupTimeline(timeline);
    _invalidatePreview();
  }

  /// Clear the active group's timeline
  void clear() {
    final group = getActiveGroup();
    if (group == null) return;

    final groupId = group.id;

    // Clear undo/redo for this group
    _undoStacks[groupId] = [];
    _redoStacks[groupId] = [];

    _updateActiveGroupTimeline(Timeline());
    _invalidatePreview();
  }

  /// Add an effect to a clip in the active group
  void addEffect(String clipId, Effect effect) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: [...clip.effects, effect],
    );
    updateClip(track.id, updatedClip);
  }

  /// Remove an effect from a clip in the active group
  void removeEffect(String clipId, String effectId) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: clip.effects.where((e) => e.id != effectId).toList(),
    );
    updateClip(track.id, updatedClip);
  }

  /// Update an effect on a clip in the active group
  void updateEffect(String clipId, Effect effect) {
    final timeline = state;
    final track = timeline.findTrackForClip(clipId);
    final clip = timeline.findClip(clipId);
    if (track == null || clip == null) return;

    final updatedClip = clip.copyWith(
      effects: clip.effects.map((e) => e.id == effect.id ? effect : e).toList(),
    );
    updateClip(track.id, updatedClip);
  }
}

/// Provider for timeline state (returns active group's timeline)
final timelineProvider =
    StateNotifierProvider<TimelineNotifier, Timeline>((ref) {
  return TimelineNotifier(ref);
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

/// Provider for timeline groups
final timelineGroupsProvider = Provider<List<TimelineGroup>>((ref) {
  // Watch the timeline state to trigger re-evaluation when it changes
  ref.watch(timelineProvider);
  return ref.read(timelineProvider.notifier).getGroups();
});

/// Provider for active timeline group
final activeTimelineGroupProvider = Provider<TimelineGroup?>((ref) {
  // Watch the timeline state to trigger re-evaluation when it changes
  ref.watch(timelineProvider);
  return ref.read(timelineProvider.notifier).getActiveGroup();
});

/// Provider for active group ID
final activeGroupIdProvider = Provider<String?>((ref) {
  // Watch the timeline state to trigger re-evaluation when it changes
  ref.watch(timelineProvider);
  return ref.read(timelineProvider.notifier).activeGroupId;
});
