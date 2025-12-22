import 'package:video_editor/core/models/models.dart';

/// Audio fade effect
class AudioFade {
  final Duration duration;
  final bool isFadeIn; // true for fade in, false for fade out

  const AudioFade({
    required this.duration,
    required this.isFadeIn,
  });

  Map<String, dynamic> toJson() => {
        'duration': duration.inMilliseconds,
        'isFadeIn': isFadeIn,
      };

  factory AudioFade.fromJson(Map<String, dynamic> json) {
    return AudioFade(
      duration: Duration(milliseconds: json['duration'] as int),
      isFadeIn: json['isFadeIn'] as bool,
    );
  }
}

/// Service for audio editing operations
class AudioService {
  /// Set volume for a clip (0.0 to 1.0)
  Clip setClipVolume(Clip clip, double volume) {
    final clampedVolume = volume.clamp(0.0, 1.0);
    return clip.copyWith(volume: clampedVolume);
  }

  /// Set volume for a track (0.0 to 1.0)
  Track setTrackVolume(Track track, double volume) {
    final clampedVolume = volume.clamp(0.0, 1.0);
    return track.copyWith(volume: clampedVolume);
  }

  /// Mute a clip
  Clip muteClip(Clip clip) {
    return clip.copyWith(isMuted: true);
  }

  /// Unmute a clip
  Clip unmuteClip(Clip clip) {
    return clip.copyWith(isMuted: false);
  }

  /// Toggle mute for a clip
  Clip toggleClipMute(Clip clip) {
    return clip.copyWith(isMuted: !clip.isMuted);
  }

  /// Mute a track
  Track muteTrack(Track track) {
    return track.copyWith(isMuted: true);
  }

  /// Unmute a track
  Track unmuteTrack(Track track) {
    return track.copyWith(isMuted: false);
  }

  /// Toggle mute for a track
  Track toggleTrackMute(Track track) {
    return track.copyWith(isMuted: !track.isMuted);
  }

  /// Lock a track (prevents editing)
  Track lockTrack(Track track) {
    return track.copyWith(isLocked: true);
  }

  /// Unlock a track
  Track unlockTrack(Track track) {
    return track.copyWith(isLocked: false);
  }

  /// Toggle lock for a track
  Track toggleTrackLock(Track track) {
    return track.copyWith(isLocked: !track.isLocked);
  }

  /// Add fade in effect to a clip
  Clip addFadeIn(Clip clip, Duration duration) {
    final fade = AudioFade(duration: duration, isFadeIn: true);
    final fadeEffect = Effect(
      name: 'Audio Fade In',
      type: 'audio_fade_in',
      parameters: fade.toJson(),
    );
    return clip.addEffect(fadeEffect);
  }

  /// Add fade out effect to a clip
  Clip addFadeOut(Clip clip, Duration duration) {
    final fade = AudioFade(duration: duration, isFadeIn: false);
    final fadeEffect = Effect(
      name: 'Audio Fade Out',
      type: 'audio_fade_out',
      parameters: fade.toJson(),
    );
    return clip.addEffect(fadeEffect);
  }

  /// Remove fade in effect from a clip
  Clip removeFadeIn(Clip clip) {
    final effects = clip.effects
        .where((effect) => effect.type != 'audio_fade_in')
        .toList();
    return clip.copyWith(effects: effects);
  }

  /// Remove fade out effect from a clip
  Clip removeFadeOut(Clip clip) {
    final effects = clip.effects
        .where((effect) => effect.type != 'audio_fade_out')
        .toList();
    return clip.copyWith(effects: effects);
  }

  /// Check if clip has fade in
  bool hasFadeIn(Clip clip) {
    return clip.effects.any((effect) => effect.type == 'audio_fade_in');
  }

  /// Check if clip has fade out
  bool hasFadeOut(Clip clip) {
    return clip.effects.any((effect) => effect.type == 'audio_fade_out');
  }

  /// Get fade in effect from clip
  Effect? getFadeIn(Clip clip) {
    try {
      return clip.effects.firstWhere((effect) => effect.type == 'audio_fade_in');
    } catch (_) {
      return null;
    }
  }

  /// Get fade out effect from clip
  Effect? getFadeOut(Clip clip) {
    try {
      return clip.effects
          .firstWhere((effect) => effect.type == 'audio_fade_out');
    } catch (_) {
      return null;
    }
  }

  /// Calculate effective volume for a clip (clip volume * track volume)
  double calculateEffectiveVolume(Clip clip, Track track) {
    if (clip.isMuted || track.isMuted) {
      return 0.0;
    }
    return clip.volume * track.volume;
  }

  /// Validate fade duration against clip duration
  bool isValidFadeDuration(Clip clip, Duration fadeDuration) {
    return fadeDuration <= clip.duration;
  }

  /// Adjust fade duration to fit clip
  Duration adjustFadeDuration(Clip clip, Duration requestedDuration) {
    // Ensure fade duration is at most 50% of clip duration
    final maxDuration = clip.duration ~/ 2;
    if (requestedDuration > maxDuration) {
      return maxDuration;
    }
    return requestedDuration;
  }
}
