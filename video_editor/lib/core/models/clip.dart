import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'effect.dart';

part 'clip.g.dart';

const _uuid = Uuid();

/// Represents a clip on the timeline
@JsonSerializable()
class Clip {
  final String id;
  final String mediaItemId;
  final Duration startTime;
  final Duration endTime;
  final Duration sourceStart;
  final Duration sourceDuration;
  final List<Effect> effects;
  final TransitionEffect? inTransition;
  final TransitionEffect? outTransition;
  final double volume; // 0.0 to 1.0
  final bool isMuted;
  final bool isVisible;

  Clip({
    String? id,
    required this.mediaItemId,
    required this.startTime,
    required this.endTime,
    required this.sourceStart,
    required this.sourceDuration,
    List<Effect>? effects,
    this.inTransition,
    this.outTransition,
    this.volume = 1.0,
    this.isMuted = false,
    this.isVisible = true,
  })  : id = id ?? _uuid.v4(),
        effects = effects ?? [];

  factory Clip.fromJson(Map<String, dynamic> json) => _$ClipFromJson(json);

  Map<String, dynamic> toJson() => _$ClipToJson(this);

  /// Duration of the clip on the timeline
  Duration get duration => endTime - startTime;

  Clip copyWith({
    String? mediaItemId,
    Duration? startTime,
    Duration? endTime,
    Duration? sourceStart,
    Duration? sourceDuration,
    List<Effect>? effects,
    TransitionEffect? inTransition,
    TransitionEffect? outTransition,
    double? volume,
    bool? isMuted,
    bool? isVisible,
  }) {
    return Clip(
      id: id,
      mediaItemId: mediaItemId ?? this.mediaItemId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      effects: effects ?? List.from(this.effects),
      inTransition: inTransition ?? this.inTransition,
      outTransition: outTransition ?? this.outTransition,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  /// Add an effect to the clip
  Clip addEffect(Effect effect) {
    return copyWith(effects: [...effects, effect]);
  }

  /// Remove an effect from the clip
  Clip removeEffect(String effectId) {
    return copyWith(
      effects: effects.where((e) => e.id != effectId).toList(),
    );
  }

  /// Update an effect in the clip
  Clip updateEffect(Effect effect) {
    return copyWith(
      effects: effects.map((e) => e.id == effect.id ? effect : e).toList(),
    );
  }
}
