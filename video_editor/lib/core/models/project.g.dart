// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
  id: json['id'] as String?,
  name: json['name'] as String,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  timeline: json['timeline'] == null
      ? null
      : Timeline.fromJson(json['timeline'] as Map<String, dynamic>),
  mediaLibrary: (json['mediaLibrary'] as List<dynamic>?)
      ?.map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  defaultExportSettings: json['defaultExportSettings'] == null
      ? null
      : ExportSettings.fromJson(
          json['defaultExportSettings'] as Map<String, dynamic>,
        ),
  maxDuration: json['maxDuration'] == null
      ? null
      : Duration(microseconds: (json['maxDuration'] as num).toInt()),
);

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'timeline': instance.timeline,
  'mediaLibrary': instance.mediaLibrary,
  'defaultExportSettings': instance.defaultExportSettings,
  'maxDuration': instance.maxDuration?.inMicroseconds,
};
