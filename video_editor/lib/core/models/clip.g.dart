// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Clip _$ClipFromJson(Map<String, dynamic> json) => Clip(
  id: json['id'] as String?,
  mediaItemId: json['mediaItemId'] as String,
  startTime: Duration(microseconds: (json['startTime'] as num).toInt()),
  endTime: Duration(microseconds: (json['endTime'] as num).toInt()),
  sourceStart: Duration(microseconds: (json['sourceStart'] as num).toInt()),
  sourceDuration: Duration(
    microseconds: (json['sourceDuration'] as num).toInt(),
  ),
  effects: (json['effects'] as List<dynamic>?)
      ?.map((e) => Effect.fromJson(e as Map<String, dynamic>))
      .toList(),
  inTransition: json['inTransition'] == null
      ? null
      : TransitionEffect.fromJson(json['inTransition'] as Map<String, dynamic>),
  outTransition: json['outTransition'] == null
      ? null
      : TransitionEffect.fromJson(
          json['outTransition'] as Map<String, dynamic>,
        ),
  volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
  isMuted: json['isMuted'] as bool? ?? false,
  isVisible: json['isVisible'] as bool? ?? true,
);

Map<String, dynamic> _$ClipToJson(Clip instance) => <String, dynamic>{
  'id': instance.id,
  'mediaItemId': instance.mediaItemId,
  'startTime': instance.startTime.inMicroseconds,
  'endTime': instance.endTime.inMicroseconds,
  'sourceStart': instance.sourceStart.inMicroseconds,
  'sourceDuration': instance.sourceDuration.inMicroseconds,
  'effects': instance.effects,
  'inTransition': instance.inTransition,
  'outTransition': instance.outTransition,
  'volume': instance.volume,
  'isMuted': instance.isMuted,
  'isVisible': instance.isVisible,
};
