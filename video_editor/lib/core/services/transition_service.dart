import 'package:video_editor/core/models/models.dart';

/// Service for managing transitions between clips
class TransitionService {
  /// Create a fade in transition
  TransitionEffect createFadeIn({Duration? duration}) {
    return TransitionEffect(
      name: 'Fade In',
      type: TransitionType.fadeIn,
      duration: duration ?? const Duration(seconds: 1),
      parameters: {},
    );
  }

  /// Create a fade out transition
  TransitionEffect createFadeOut({Duration? duration}) {
    return TransitionEffect(
      name: 'Fade Out',
      type: TransitionType.fadeOut,
      duration: duration ?? const Duration(seconds: 1),
      parameters: {},
    );
  }

  /// Create a cross fade transition
  TransitionEffect createCrossFade({Duration? duration}) {
    return TransitionEffect(
      name: 'Cross Fade',
      type: TransitionType.crossFade,
      duration: duration ?? const Duration(milliseconds: 500),
      parameters: {},
    );
  }

  /// Create a wipe transition
  TransitionEffect createWipe({
    Duration? duration,
    String direction = 'left', // left, right, up, down
  }) {
    return TransitionEffect(
      name: 'Wipe',
      type: TransitionType.wipe,
      duration: duration ?? const Duration(milliseconds: 500),
      parameters: {'direction': direction},
    );
  }

  /// Create a slide transition
  TransitionEffect createSlide({
    Duration? duration,
    String direction = 'left', // left, right, up, down
  }) {
    return TransitionEffect(
      name: 'Slide',
      type: TransitionType.slide,
      duration: duration ?? const Duration(milliseconds: 500),
      parameters: {'direction': direction},
    );
  }

  /// Create a zoom transition
  TransitionEffect createZoom({
    Duration? duration,
    String type = 'in', // in, out
  }) {
    return TransitionEffect(
      name: 'Zoom',
      type: TransitionType.zoom,
      duration: duration ?? const Duration(milliseconds: 500),
      parameters: {'zoomType': type},
    );
  }

  /// Apply an in-transition to a clip
  Clip applyInTransition(Clip clip, TransitionEffect transition) {
    return clip.copyWith(inTransition: transition);
  }

  /// Apply an out-transition to a clip
  Clip applyOutTransition(Clip clip, TransitionEffect transition) {
    return clip.copyWith(outTransition: transition);
  }

  /// Remove in-transition from a clip
  Clip removeInTransition(Clip clip) {
    return clip.copyWith(inTransition: null);
  }

  /// Remove out-transition from a clip
  Clip removeOutTransition(Clip clip) {
    return clip.copyWith(outTransition: null);
  }

  /// Get default transition for auto-editing
  TransitionEffect getDefaultTransition() {
    return createCrossFade();
  }

  /// Get all available transition types
  List<TransitionType> getAvailableTransitions() {
    return TransitionType.values;
  }

  /// Get transition name for display
  String getTransitionName(TransitionType type) {
    switch (type) {
      case TransitionType.fadeIn:
        return 'Fade In';
      case TransitionType.fadeOut:
        return 'Fade Out';
      case TransitionType.crossFade:
        return 'Cross Fade';
      case TransitionType.wipe:
        return 'Wipe';
      case TransitionType.slide:
        return 'Slide';
      case TransitionType.zoom:
        return 'Zoom';
    }
  }

  /// Validate transition duration against clip duration
  bool isValidTransitionDuration(Clip clip, Duration transitionDuration) {
    // Transition should not exceed clip duration
    return transitionDuration <= clip.duration;
  }

  /// Adjust transition duration to fit clip
  Duration adjustTransitionDuration(Clip clip, Duration requestedDuration) {
    if (requestedDuration > clip.duration) {
      return clip.duration;
    }
    return requestedDuration;
  }

  /// Calculate overlap between two clips for cross-fade
  Duration? calculateCrossFadeOverlap(Clip clip1, Clip clip2) {
    // Check if clips are adjacent or overlapping
    if (clip2.startTime >= clip1.endTime) {
      // Clips are not adjacent
      return null;
    }

    // Calculate overlap duration
    final overlap = clip1.endTime - clip2.startTime;
    return overlap;
  }
}
