// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Timeline _$TimelineFromJson(Map<String, dynamic> json) => Timeline(
  id: json['id'] as String?,
  tracks: (json['tracks'] as List<dynamic>?)
      ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
      .toList(),
  currentPosition: json['currentPosition'] == null
      ? Duration.zero
      : Duration(microseconds: (json['currentPosition'] as num).toInt()),
);

Map<String, dynamic> _$TimelineToJson(Timeline instance) => <String, dynamic>{
  'id': instance.id,
  'tracks': instance.tracks,
  'currentPosition': instance.currentPosition.inMicroseconds,
};
