// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TimelineGroup _$TimelineGroupFromJson(Map<String, dynamic> json) =>
    TimelineGroup(
      id: json['id'] as String?,
      name: json['name'] as String,
      timeline: json['timeline'] == null
          ? null
          : Timeline.fromJson(json['timeline'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TimelineGroupToJson(TimelineGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'timeline': instance.timeline,
    };
