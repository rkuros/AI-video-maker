import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'enums.dart';
import 'media_info.dart';

part 'effect.g.dart';

const _uuid = Uuid();

/// Base class for all effects
@JsonSerializable()
class Effect {
  final String id;
  final String name;
  final String type;
  final Map<String, dynamic> parameters;

  Effect({
    String? id,
    required this.name,
    required this.type,
    required this.parameters,
  }) : id = id ?? _uuid.v4();

  factory Effect.fromJson(Map<String, dynamic> json) => _$EffectFromJson(json);

  Map<String, dynamic> toJson() => _$EffectToJson(this);

  Effect copyWith({
    String? name,
    String? type,
    Map<String, dynamic>? parameters,
  }) {
    return Effect(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      parameters: parameters ?? Map.from(this.parameters),
    );
  }
}

/// Color adjustment effect (brightness, contrast, saturation)
class ColorAdjustmentEffect extends Effect {
  ColorAdjustmentEffect({
    super.id,
    double brightness = 0.0, // -1.0 to 1.0
    double contrast = 0.0, // -1.0 to 1.0
    double saturation = 0.0, // -1.0 to 1.0
    double intensity = 1.0, // 0.0 to 1.0
  }) : super(
          name: 'Color Adjustment',
          type: 'color_adjustment',
          parameters: {
            'brightness': brightness,
            'contrast': contrast,
            'saturation': saturation,
            'intensity': intensity,
          },
        );

  factory ColorAdjustmentEffect.fromJson(Map<String, dynamic> json) =>
      ColorAdjustmentEffect(
        id: json['id'] as String?,
        brightness: (json['parameters']['brightness'] as num).toDouble(),
        contrast: (json['parameters']['contrast'] as num).toDouble(),
        saturation: (json['parameters']['saturation'] as num).toDouble(),
        intensity: (json['parameters']['intensity'] as num).toDouble(),
      );
}

/// Filter effect (sepia, monochrome, vintage, etc.)
class FilterEffect extends Effect {
  FilterEffect({
    super.id,
    required String filterType,
    double intensity = 1.0, // 0.0 to 1.0
  }) : super(
          name: 'Filter: $filterType',
          type: 'filter',
          parameters: {
            'filterType': filterType,
            'intensity': intensity,
          },
        );

  factory FilterEffect.fromJson(Map<String, dynamic> json) => FilterEffect(
        id: json['id'] as String?,
        filterType: json['parameters']['filterType'] as String,
        intensity: (json['parameters']['intensity'] as num).toDouble(),
      );
}

/// Low-light denoise effect
class LowLightDenoiseEffect extends Effect {
  final DenoiseSettings settings;

  LowLightDenoiseEffect({
    super.id,
    required this.settings,
  }) : super(
          name: 'Low Light Denoise',
          type: 'low_light_denoise',
          parameters: settings.toJson(),
        );

  factory LowLightDenoiseEffect.fromJson(Map<String, dynamic> json) =>
      LowLightDenoiseEffect(
        id: json['id'] as String?,
        settings:
            DenoiseSettings.fromJson(json['parameters'] as Map<String, dynamic>),
      );
}

/// Auto denoise effect with automatic analysis
class AutoDenoiseEffect extends Effect {
  final DenoiseSettings settings;
  final bool autoMode;

  AutoDenoiseEffect({
    super.id,
    required this.settings,
    this.autoMode = true,
  }) : super(
          name: autoMode ? 'Auto Denoise' : 'Advanced Denoise',
          type: 'auto_denoise',
          parameters: {
            ...settings.toJson(),
            'autoMode': autoMode,
          },
        );

  factory AutoDenoiseEffect.fromJson(Map<String, dynamic> json) =>
      AutoDenoiseEffect(
        id: json['id'] as String?,
        settings:
            DenoiseSettings.fromJson(json['parameters'] as Map<String, dynamic>),
        autoMode: json['parameters']['autoMode'] as bool? ?? true,
      );
}

/// Transition effect between clips
@JsonSerializable()
class TransitionEffect {
  final String id;
  final String name;
  final Duration duration;
  final TransitionType type;
  final Map<String, dynamic> parameters;

  TransitionEffect({
    String? id,
    required this.name,
    required this.duration,
    required this.type,
    Map<String, dynamic>? parameters,
  })  : id = id ?? _uuid.v4(),
        parameters = parameters ?? {};

  factory TransitionEffect.fromJson(Map<String, dynamic> json) =>
      _$TransitionEffectFromJson(json);

  Map<String, dynamic> toJson() => _$TransitionEffectToJson(this);

  TransitionEffect copyWith({
    String? name,
    Duration? duration,
    TransitionType? type,
    Map<String, dynamic>? parameters,
  }) {
    return TransitionEffect(
      id: id,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      type: type ?? this.type,
      parameters: parameters ?? Map.from(this.parameters),
    );
  }
}
