import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/transition_service.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';

/// Provider for transition service
final transitionServiceProvider = Provider<TransitionService>((ref) {
  return TransitionService();
});

/// State for selected transition settings
class TransitionSettingsState {
  final TransitionType type;
  final Duration duration;
  final Map<String, dynamic> parameters;

  const TransitionSettingsState({
    this.type = TransitionType.crossFade,
    this.duration = const Duration(milliseconds: 500),
    this.parameters = const {},
  });

  TransitionSettingsState copyWith({
    TransitionType? type,
    Duration? duration,
    Map<String, dynamic>? parameters,
  }) {
    return TransitionSettingsState(
      type: type ?? this.type,
      duration: duration ?? this.duration,
      parameters: parameters ?? this.parameters,
    );
  }
}

/// Notifier for transition settings
class TransitionSettingsNotifier extends StateNotifier<TransitionSettingsState> {
  TransitionSettingsNotifier() : super(const TransitionSettingsState());

  void setType(TransitionType type) {
    state = state.copyWith(type: type);
  }

  void setDuration(Duration duration) {
    // Clamp duration between 0.1s and 5s
    final clampedDuration = Duration(
      milliseconds: duration.inMilliseconds.clamp(100, 5000),
    );
    state = state.copyWith(duration: clampedDuration);
  }

  void setParameter(String key, dynamic value) {
    final newParams = Map<String, dynamic>.from(state.parameters);
    newParams[key] = value;
    state = state.copyWith(parameters: newParams);
  }

  void reset() {
    state = const TransitionSettingsState();
  }
}

/// Provider for transition settings
final transitionSettingsProvider =
    StateNotifierProvider<TransitionSettingsNotifier, TransitionSettingsState>(
        (ref) {
  return TransitionSettingsNotifier();
});

/// Helper class for transition operations
class TransitionOperations {
  final Ref ref;

  TransitionOperations(this.ref);

  bool _requiresOverlap(TransitionEffect transition) {
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
  }

  void _overlapWithPreviousClip(
    String trackId,
    String clipId,
    Duration overlap,
  ) {
    if (overlap <= Duration.zero) return;

    final timeline = ref.read(timelineProvider);
    final track = timeline.getTrack(trackId);
    if (track == null || track.type != TrackType.video) return;

    final clips = List<Clip>.from(track.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index <= 0) return;

    final previous = clips[index - 1];
    final current = clips[index];

    // Make the transition overlap sit right at the cut point: gap == -overlap.
    var start = previous.endTime - overlap;
    if (start < Duration.zero) start = Duration.zero;

    // Avoid moving earlier than the previous clip's start (handles).
    if (start < previous.startTime) {
      start = previous.startTime;
    }

    if (start >= current.startTime) return;
    ref.read(timelineProvider.notifier).moveClip(clipId, start);
  }

  void _overlapWithNextClip(
    String trackId,
    String clipId,
    Duration overlap,
  ) {
    if (overlap <= Duration.zero) return;

    final timeline = ref.read(timelineProvider);
    final track = timeline.getTrack(trackId);
    if (track == null || track.type != TrackType.video) return;

    final clips = List<Clip>.from(track.clips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final index = clips.indexWhere((c) => c.id == clipId);
    if (index < 0 || index >= clips.length - 1) return;

    final current = clips[index];
    final next = clips[index + 1];

    var start = current.endTime - overlap;
    if (start < Duration.zero) start = Duration.zero;

    if (start >= next.startTime) return;
    ref.read(timelineProvider.notifier).moveClip(next.id, start);
  }

  /// Apply an in-transition to a clip
  void applyInTransition(String trackId, String clipId) {
    final service = ref.read(transitionServiceProvider);
    final settings = ref.read(transitionSettingsProvider);
    final timeline = ref.read(timelineProvider);

    // Find the clip
    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Create transition based on settings
    final transition = _createTransition(service, settings);

    // Apply transition
    final updatedClip = service.applyInTransition(clip, transition);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);

    // Non-fade transitions are rendered via `xfade`, which requires overlap.
    if (_requiresOverlap(transition)) {
      _overlapWithPreviousClip(trackId, clipId, transition.duration);
    }
  }

  /// Apply an out-transition to a clip
  void applyOutTransition(String trackId, String clipId) {
    final service = ref.read(transitionServiceProvider);
    final settings = ref.read(transitionSettingsProvider);
    final timeline = ref.read(timelineProvider);

    // Find the clip
    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Create transition based on settings
    final transition = _createTransition(service, settings);

    // Apply transition
    final updatedClip = service.applyOutTransition(clip, transition);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);

    // If this is an xfade-style transition, overlap the next clip.
    if (_requiresOverlap(transition)) {
      _overlapWithNextClip(trackId, clipId, transition.duration);
    }
  }

  /// Remove in-transition from a clip
  void removeInTransition(String trackId, String clipId) {
    final service = ref.read(transitionServiceProvider);
    final timeline = ref.read(timelineProvider);

    // Find the clip
    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Remove transition
    final updatedClip = service.removeInTransition(clip);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Remove out-transition from a clip
  void removeOutTransition(String trackId, String clipId) {
    final service = ref.read(transitionServiceProvider);
    final timeline = ref.read(timelineProvider);

    // Find the clip
    final clip = timeline.findClip(clipId);
    if (clip == null) return;

    // Remove transition
    final updatedClip = service.removeOutTransition(clip);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip);
  }

  /// Apply cross-fade between adjacent clips
  void applyCrossFadeBetweenClips(
    String trackId,
    String clip1Id,
    String clip2Id,
  ) {
    final service = ref.read(transitionServiceProvider);
    final settings = ref.read(transitionSettingsProvider);
    final timeline = ref.read(timelineProvider);

    // Find the clips
    final clip1 = timeline.findClip(clip1Id);
    final clip2 = timeline.findClip(clip2Id);
    if (clip1 == null || clip2 == null) return;

    // Create cross-fade transition
    final transition = service.createCrossFade(duration: settings.duration);

    // Apply out-transition to first clip
    var updatedClip1 = service.applyOutTransition(clip1, transition);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip1);

    // Apply in-transition to second clip
    var updatedClip2 = service.applyInTransition(clip2, transition);
    ref.read(timelineProvider.notifier).updateClip(trackId, updatedClip2);

    _overlapWithPreviousClip(trackId, clip2Id, transition.duration);
  }

  TransitionEffect _createTransition(
    TransitionService service,
    TransitionSettingsState settings,
  ) {
    switch (settings.type) {
      case TransitionType.fadeIn:
        return service.createFadeIn(duration: settings.duration);
      case TransitionType.fadeOut:
        return service.createFadeOut(duration: settings.duration);
      case TransitionType.crossFade:
        return service.createCrossFade(duration: settings.duration);
      case TransitionType.wipe:
        return service.createWipe(
          duration: settings.duration,
          direction: settings.parameters['direction'] as String? ?? 'left',
        );
      case TransitionType.slide:
        return service.createSlide(
          duration: settings.duration,
          direction: settings.parameters['direction'] as String? ?? 'left',
        );
      case TransitionType.zoom:
        return service.createZoom(
          duration: settings.duration,
          type: settings.parameters['zoomType'] as String? ?? 'in',
        );
    }
  }
}

/// Provider for transition operations
final transitionOperationsProvider = Provider<TransitionOperations>((ref) {
  return TransitionOperations(ref);
});
