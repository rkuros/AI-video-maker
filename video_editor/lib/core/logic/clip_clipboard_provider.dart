import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/clip.dart';
import 'package:video_editor/core/models/effect.dart';

class ClipClipboardEntry {
  final Clip clip;
  final String sourceTrackId;

  const ClipClipboardEntry({required this.clip, required this.sourceTrackId});

  Clip materializeAt(Duration startTime) {
    final duration = clip.sourceDuration > Duration.zero
        ? clip.sourceDuration
        : clip.duration;

    Effect cloneEffect(Effect effect) {
      return Effect(
        name: effect.name,
        type: effect.type,
        parameters: Map<String, dynamic>.from(effect.parameters),
      );
    }

    TransitionEffect? cloneTransition(TransitionEffect? transition) {
      if (transition == null) return null;
      return TransitionEffect(
        name: transition.name,
        duration: transition.duration,
        type: transition.type,
        parameters: Map<String, dynamic>.from(transition.parameters),
      );
    }

    return Clip(
      mediaItemId: clip.mediaItemId,
      startTime: startTime,
      endTime: startTime + duration,
      sourceStart: clip.sourceStart,
      sourceDuration: duration,
      effects: clip.effects.map(cloneEffect).toList(),
      inTransition: cloneTransition(clip.inTransition),
      outTransition: cloneTransition(clip.outTransition),
      volume: clip.volume,
      isMuted: clip.isMuted,
      isVisible: clip.isVisible,
    );
  }
}

final clipClipboardProvider = StateProvider<ClipClipboardEntry?>((ref) => null);
