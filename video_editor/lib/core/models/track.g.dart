// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Track _$TrackFromJson(Map<String, dynamic> json) => Track(
  id: json['id'] as String?,
  type: $enumDecode(_$TrackTypeEnumMap, json['type']),
  clips: (json['clips'] as List<dynamic>?)
      ?.map((e) => Clip.fromJson(e as Map<String, dynamic>))
      .toList(),
  isLocked: json['isLocked'] as bool? ?? false,
  isMuted: json['isMuted'] as bool? ?? false,
  isVisible: json['isVisible'] as bool? ?? true,
  name: json['name'] as String?,
  volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
);

Map<String, dynamic> _$TrackToJson(Track instance) => <String, dynamic>{
  'id': instance.id,
  'type': _$TrackTypeEnumMap[instance.type]!,
  'clips': instance.clips,
  'isLocked': instance.isLocked,
  'isMuted': instance.isMuted,
  'isVisible': instance.isVisible,
  'name': instance.name,
  'volume': instance.volume,
};

const _$TrackTypeEnumMap = {TrackType.video: 'video', TrackType.audio: 'audio'};
