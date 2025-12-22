// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'beat.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BeatMarker _$BeatMarkerFromJson(Map<String, dynamic> json) => BeatMarker(
  timestamp: Duration(microseconds: (json['timestamp'] as num).toInt()),
  intensity: (json['intensity'] as num).toDouble(),
  type: $enumDecode(_$BeatTypeEnumMap, json['type']),
);

Map<String, dynamic> _$BeatMarkerToJson(BeatMarker instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp.inMicroseconds,
      'intensity': instance.intensity,
      'type': _$BeatTypeEnumMap[instance.type]!,
    };

const _$BeatTypeEnumMap = {
  BeatType.strong: 'strong',
  BeatType.weak: 'weak',
  BeatType.accent: 'accent',
};

BeatAnalysisResult _$BeatAnalysisResultFromJson(Map<String, dynamic> json) =>
    BeatAnalysisResult(
      beats: (json['beats'] as List<dynamic>)
          .map((e) => BeatMarker.fromJson(e as Map<String, dynamic>))
          .toList(),
      bpm: (json['bpm'] as num).toDouble(),
      totalDuration: Duration(
        microseconds: (json['totalDuration'] as num).toInt(),
      ),
    );

Map<String, dynamic> _$BeatAnalysisResultToJson(BeatAnalysisResult instance) =>
    <String, dynamic>{
      'beats': instance.beats,
      'bpm': instance.bpm,
      'totalDuration': instance.totalDuration.inMicroseconds,
    };
