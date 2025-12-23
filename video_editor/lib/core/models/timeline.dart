import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'track.dart';
import 'clip.dart';
import 'effect.dart';
import 'enums.dart';

part 'timeline.g.dart';

const _uuid = Uuid();

/// Represents the timeline containing all tracks and clips
@JsonSerializable()
class Timeline {
  final String id;
  final List<Track> tracks;
  final Duration currentPosition;

  Timeline({
    String? id,
    List<Track>? tracks,
    this.currentPosition = Duration.zero,
  })  : id = id ?? _uuid.v4(),
        tracks = tracks ?? [];

  factory Timeline.fromJson(Map<String, dynamic> json) =>
      _$TimelineFromJson(json);

  Map<String, dynamic> toJson() => _$TimelineToJson(this);

  /// Get the total duration of the timeline
  Duration get duration {
    if (tracks.isEmpty) return Duration.zero;
    return tracks.map((t) => t.duration).reduce((a, b) => a > b ? a : b);
  }

  /// Get all video tracks
  List<Track> get videoTracks =>
      tracks.where((t) => t.type == TrackType.video).toList();

  /// Get all audio tracks
  List<Track> get audioTracks =>
      tracks.where((t) => t.type == TrackType.audio).toList();

  Timeline copyWith({
    List<Track>? tracks,
    Duration? currentPosition,
  }) {
    return Timeline(
      id: id,
      tracks: tracks ?? List.from(this.tracks),
      currentPosition: currentPosition ?? this.currentPosition,
    );
  }

  /// Add a track to the timeline (prepends to the list so it appears on top)
  Timeline addTrack(Track track) {
    return copyWith(tracks: [track, ...tracks]);
  }

  /// Remove a track from the timeline
  Timeline removeTrack(String trackId) {
    return copyWith(
      tracks: tracks.where((t) => t.id != trackId).toList(),
    );
  }

  /// Update a track in the timeline
  Timeline updateTrack(Track track) {
    return copyWith(
      tracks: tracks.map((t) => t.id == track.id ? track : t).toList(),
    );
  }

  /// Get a track by ID
  Track? getTrack(String trackId) {
    try {
      return tracks.firstWhere((t) => t.id == trackId);
    } catch (_) {
      return null;
    }
  }

  /// Add a clip to a specific track
  Timeline addClipToTrack(String trackId, Clip clip) {
    final track = getTrack(trackId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final updatedTrack = _insertClipWithoutTrimming(track, clip);
    return updateTrack(updatedTrack);
  }

  /// Remove a clip from a track
  Timeline removeClipFromTrack(String trackId, String clipId) {
    final track = getTrack(trackId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final updatedTrack = track.removeClip(clipId);
    return updateTrack(updatedTrack);
  }

  /// Update a clip in a track
  Timeline updateClipInTrack(String trackId, Clip clip) {
    final track = getTrack(trackId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final updatedTrack = track.updateClip(clip);
    return updateTrack(updatedTrack);
  }

  /// Find a clip by ID across all tracks
  Clip? findClip(String clipId) {
    for (final track in tracks) {
      final clip = track.getClip(clipId);
      if (clip != null) return clip;
    }
    return null;
  }

  /// Find the track containing a specific clip
  Track? findTrackForClip(String clipId) {
    for (final track in tracks) {
      if (track.getClip(clipId) != null) return track;
    }
    return null;
  }

  /// Move a clip to a new position on the same track
  Timeline moveClip(String clipId, Duration newStartTime) {
    final track = findTrackForClip(clipId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final clip = track.getClip(clipId);
    if (clip == null) return this;

    var desiredStart = newStartTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;

    final remainingClips = track.clips.where((c) => c.id != clipId).toList();

    // Use the actual clip duration (which reflects trimming), not sourceDuration
    final clipDuration = clip.duration;
    final moved = clip.copyWith(
      startTime: desiredStart,
      endTime: desiredStart + clipDuration,
    );

    final updatedTrack = _insertClipWithoutTrimming(
      track.copyWith(clips: remainingClips),
      moved,
    );
    return updateTrack(updatedTrack);
  }

  Duration _clipDurationForInsert(Clip clip) {
    if (clip.sourceDuration > Duration.zero) return clip.sourceDuration;
    return clip.duration;
  }

  bool _isXfadeTransition(TransitionEffect? transition) {
    if (transition == null) return false;
    switch (transition.type) {
      case TransitionType.fadeIn:
      case TransitionType.fadeOut:
        return false;
      case TransitionType.crossFade:
      case TransitionType.wipe:
      case TransitionType.slide:
      case TransitionType.zoom:
        return true;
    }
    // Defensive fallback in case new enum values are added.
    // (Switch should be exhaustive today.)
    // ignore: dead_code
    return false;
  }

  Duration _maxAllowedOverlap(Clip previous, Clip current) {
    final TransitionEffect? transition;
    if (_isXfadeTransition(current.inTransition)) {
      transition = current.inTransition;
    } else if (_isXfadeTransition(previous.outTransition)) {
      transition = previous.outTransition;
    } else {
      transition = null;
    }
    if (transition == null) return Duration.zero;

    final requested = transition.duration;
    if (requested <= Duration.zero) return Duration.zero;

    final maxMs = min(
      _clipDurationForInsert(previous).inMilliseconds,
      _clipDurationForInsert(current).inMilliseconds,
    );
    if (maxMs <= 0) return Duration.zero;
    final maxAllowed = Duration(milliseconds: maxMs);
    return requested <= maxAllowed ? requested : maxAllowed;
  }

  Track _insertClipWithoutTrimming(Track track, Clip clip) {
    // Use the actual clip duration (respects trimming)
    final clipDuration = clip.duration;
    var desiredStart = clip.startTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;

    final sorted = List<Clip>.from(track.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // If inserting inside an existing clip, snap to that clip's end unless a
    // transition explicitly allows a bounded overlap with the previous clip.
    Clip? collidingPrevious;
    for (final c in sorted) {
      if (c.startTime <= desiredStart && desiredStart < c.endTime) {
        collidingPrevious = c;
      }
    }
    if (collidingPrevious != null) {
      final allowedOverlap = _maxAllowedOverlap(collidingPrevious, clip);
      if (allowedOverlap > Duration.zero) {
        final overlap = collidingPrevious.endTime - desiredStart;
        if (overlap > allowedOverlap) {
          desiredStart = collidingPrevious.endTime - allowedOverlap;
        }
      } else {
        desiredStart = collidingPrevious.endTime;
      }
    }

    final inserted = clip.copyWith(
      startTime: desiredStart,
      endTime: desiredStart + clipDuration,
    );

    final before = <Clip>[];
    final after = <Clip>[];
    for (final c in sorted) {
      if (c.startTime < inserted.startTime) {
        before.add(c);
      } else {
        after.add(c);
      }
    }

    var currentEnd = inserted.endTime;
    final shiftedAfter = <Clip>[];
    for (final c in after) {
      // Use the actual clip duration (respects trimming)
      final d = c.duration;
      if (c.startTime < currentEnd) {
        final shifted = c.copyWith(
          startTime: currentEnd,
          endTime: currentEnd + d,
        );
        shiftedAfter.add(shifted);
        currentEnd = shifted.endTime;
      } else {
        shiftedAfter.add(c);
        currentEnd = c.endTime;
      }
    }

    final newClips = [...before, inserted, ...shiftedAfter]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return track.copyWith(clips: newClips);
  }

  /// Trim a clip's start and end points
  Timeline trimClip(String clipId, Duration newStart, Duration newEnd) {
    final track = findTrackForClip(clipId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final clip = track.getClip(clipId);
    if (clip == null) return this;

    if (newEnd <= newStart) return this;

    // Keep timeline trimming consistent with source trimming:
    // - Moving start forward increases sourceStart.
    // - Clip duration always matches sourceDuration.
    // - If trimming would seek before the media start, clamp both sourceStart and
    //   timeline start while keeping the end time fixed.
    var desiredStart = newStart < Duration.zero ? Duration.zero : newStart;
    final desiredEnd = newEnd;
    if (desiredEnd <= desiredStart) return this;

    var desiredDuration = desiredEnd - desiredStart;

    final startDelta = desiredStart - clip.startTime;
    var newSourceStart = clip.sourceStart + startDelta;
    var effectiveStart = desiredStart;
    if (newSourceStart < Duration.zero) {
      // Can't seek before start of media. Clamp the start, but keep the end fixed.
      effectiveStart = clip.startTime - clip.sourceStart;
      if (effectiveStart < Duration.zero) effectiveStart = Duration.zero;
      newSourceStart = Duration.zero;
      if (desiredEnd <= effectiveStart) return this;
      desiredStart = effectiveStart;
      desiredDuration = desiredEnd - effectiveStart;
    }

    var updatedClip = clip.copyWith(
      startTime: effectiveStart,
      endTime: effectiveStart + desiredDuration,
      sourceStart: newSourceStart,
      sourceDuration: desiredDuration,
    );

    // Prevent extending the clip start into the previous clip beyond any
    // transition-allowed overlap. When clamping, keep the end time fixed (like
    // a left-handle trim) and adjust sourceStart/sourceDuration accordingly.
    final sortedAfterUpdate = List<Clip>.from(track.updateClip(updatedClip).clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final index = sortedAfterUpdate.indexWhere((c) => c.id == updatedClip.id);
    if (index > 0) {
      final previous = sortedAfterUpdate[index - 1];
      final allowedOverlap = _maxAllowedOverlap(previous, updatedClip);
      final minStart = previous.endTime - allowedOverlap;
      if (updatedClip.startTime < minStart) {
        final delta = minStart - updatedClip.startTime;
        final clampedStart = minStart < Duration.zero ? Duration.zero : minStart;
        if (updatedClip.endTime <= clampedStart) return this;
        updatedClip = updatedClip.copyWith(
          startTime: clampedStart,
          sourceStart: updatedClip.sourceStart + delta,
          sourceDuration: updatedClip.endTime - clampedStart,
        );
      }
    }

    final updatedTrack = _rippleShiftAfter(
      track.updateClip(updatedClip),
      updatedClip.id,
    );
    return updateTrack(updatedTrack);
  }

  Track _rippleShiftAfter(Track track, String clipId) {
    final sorted = List<Clip>.from(track.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final index = sorted.indexWhere((c) => c.id == clipId);
    if (index < 0) return track;

    var currentEnd = sorted[index].endTime;
    for (var i = index + 1; i < sorted.length; i++) {
      final current = sorted[i];
      final previous = sorted[i - 1];
      final allowedOverlap = _maxAllowedOverlap(previous, current);
      final minStart = currentEnd - allowedOverlap;
      if (current.startTime < minStart) {
        // Use the actual clip duration (respects trimming)
        final d = current.duration;
        final shiftedStart = minStart < Duration.zero ? Duration.zero : minStart;
        final shifted = current.copyWith(
          startTime: shiftedStart,
          endTime: shiftedStart + d,
        );
        sorted[i] = shifted;
        currentEnd = shifted.endTime;
      } else {
        currentEnd = current.endTime;
      }
    }

    return track.copyWith(clips: sorted);
  }

  /// Split a clip at a specific position
  Timeline splitClip(String clipId, Duration splitPosition) {
    final track = findTrackForClip(clipId);
    if (track == null) return this;
    if (track.isLocked) return this;

    final clip = track.getClip(clipId);
    if (clip == null) return this;

    // Check if split position is within the clip
    if (splitPosition <= clip.startTime || splitPosition >= clip.endTime) {
      return this;
    }

    // Calculate source offsets
    final timeFromStart = splitPosition - clip.startTime;
    final sourceOffset = clip.sourceStart + timeFromStart;

    // Create first clip (before split)
    final firstClip = clip.copyWith(
      endTime: splitPosition,
      sourceDuration: timeFromStart,
    );

    // Create second clip (after split)
    final secondClip = Clip(
      mediaItemId: clip.mediaItemId,
      startTime: splitPosition,
      endTime: clip.endTime,
      sourceStart: sourceOffset,
      sourceDuration: clip.endTime - splitPosition,
      effects: List.from(clip.effects),
      volume: clip.volume,
      isMuted: clip.isMuted,
    );

    // Update track with both clips
    var updatedTrack = track.removeClip(clipId);
    updatedTrack = updatedTrack.addClip(firstClip);
    updatedTrack = updatedTrack.addClip(secondClip);

    return updateTrack(updatedTrack);
  }
}
