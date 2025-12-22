// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'effect.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Effect _$EffectFromJson(Map<String, dynamic> json) => Effect(
  id: json['id'] as String?,
  name: json['name'] as String,
  type: json['type'] as String,
  parameters: json['parameters'] as Map<String, dynamic>,
);

Map<String, dynamic> _$EffectToJson(Effect instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'type': instance.type,
  'parameters': instance.parameters,
};

TransitionEffect _$TransitionEffectFromJson(Map<String, dynamic> json) =>
    TransitionEffect(
      id: json['id'] as String?,
      name: json['name'] as String,
      duration: Duration(microseconds: (json['duration'] as num).toInt()),
      type: $enumDecode(_$TransitionTypeEnumMap, json['type']),
      parameters: json['parameters'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$TransitionEffectToJson(TransitionEffect instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'duration': instance.duration.inMicroseconds,
      'type': _$TransitionTypeEnumMap[instance.type]!,
      'parameters': instance.parameters,
    };

const _$TransitionTypeEnumMap = {
  TransitionType.fadeIn: 'fadeIn',
  TransitionType.fadeOut: 'fadeOut',
  TransitionType.crossFade: 'crossFade',
  TransitionType.wipe: 'wipe',
  TransitionType.slide: 'slide',
  TransitionType.zoom: 'zoom',
};
