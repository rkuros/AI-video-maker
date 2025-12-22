// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
  id: json['id'] as String?,
  name: json['name'] as String,
  filePath: json['filePath'] as String,
  type: $enumDecode(_$MediaTypeEnumMap, json['type']),
  duration: Duration(microseconds: (json['duration'] as num).toInt()),
  videoInfo: json['videoInfo'] == null
      ? null
      : VideoInfo.fromJson(json['videoInfo'] as Map<String, dynamic>),
  audioInfo: json['audioInfo'] == null
      ? null
      : AudioInfo.fromJson(json['audioInfo'] as Map<String, dynamic>),
);

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'filePath': instance.filePath,
  'type': _$MediaTypeEnumMap[instance.type]!,
  'duration': instance.duration.inMicroseconds,
  'videoInfo': instance.videoInfo,
  'audioInfo': instance.audioInfo,
};

const _$MediaTypeEnumMap = {
  MediaType.video: 'video',
  MediaType.audio: 'audio',
  MediaType.image: 'image',
};
