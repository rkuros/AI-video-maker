import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/services/audio_service.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';

/// Provider for audio service
final audioServiceProvider = Provider<AudioService>((ref) {
  return AudioService();
});

/// Helper class for audio operations
class AudioOperations {
  final Ref ref;

  AudioOperations(this.ref);

  /// Set clip volume
  void setClipVolume(String trackId, String clipId, double volume) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    final updatedClip = service.setClipVolume(clip, volume);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Set track volume
  void setTrackVolume(String trackId, double volume) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final track = timeline.getTrack(trackId);
    if (track == null) return;

    final updatedTrack = service.setTrackVolume(track, volume);
    ref.read(timelineProvider.notifier).updateTrack(updatedTrack);
  }

  /// Toggle clip mute
  void toggleClipMute(String trackId, String clipId) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    final updatedClip = service.toggleClipMute(clip);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Toggle track mute
  void toggleTrackMute(String trackId) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final track = timeline.getTrack(trackId);
    if (track == null) return;

    final updatedTrack = service.toggleTrackMute(track);
    ref.read(timelineProvider.notifier).updateTrack(updatedTrack);
  }

  /// Toggle track lock
  void toggleTrackLock(String trackId) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final track = timeline.getTrack(trackId);
    if (track == null) return;

    final updatedTrack = service.toggleTrackLock(track);
    ref.read(timelineProvider.notifier).updateTrack(updatedTrack);
  }

  /// Add fade in to clip
  void addFadeIn(String trackId, String clipId, Duration duration) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Validate and adjust duration
    final adjustedDuration = service.adjustFadeDuration(clip, duration);
    final updatedClip = service.addFadeIn(clip, adjustedDuration);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Add fade out to clip
  void addFadeOut(String trackId, String clipId, Duration duration) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Validate and adjust duration
    final adjustedDuration = service.adjustFadeDuration(clip, duration);
    final updatedClip = service.addFadeOut(clip, adjustedDuration);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Remove fade in from clip
  void removeFadeIn(String trackId, String clipId) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    final updatedClip = service.removeFadeIn(clip);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Remove fade out from clip
  void removeFadeOut(String trackId, String clipId) {
    final service = ref.read(audioServiceProvider);
    final timeline = ref.read(timelineProvider);

    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    final updatedClip = service.removeFadeOut(clip);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }
}

/// Provider for audio operations
final audioOperationsProvider = Provider<AudioOperations>((ref) {
  return AudioOperations(ref);
});
