// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExportSettings _$ExportSettingsFromJson(
  Map<String, dynamic> json,
) => ExportSettings(
  outputPath: json['outputPath'] as String? ?? '',
  format:
      $enumDecodeNullable(_$VideoFormatEnumMap, json['format']) ??
      VideoFormat.mp4,
  resolution:
      $enumDecodeNullable(_$ResolutionEnumMap, json['resolution']) ??
      Resolution.r1080p,
  quality:
      $enumDecodeNullable(_$QualityEnumMap, json['quality']) ?? Quality.high,
  frameRate: (json['frameRate'] as num?)?.toInt() ?? 30,
  videoPreset: json['videoPreset'] as String? ?? 'medium',
  audioSettings: json['audioSettings'] == null
      ? null
      : AudioSettings.fromJson(json['audioSettings'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ExportSettingsToJson(ExportSettings instance) =>
    <String, dynamic>{
      'outputPath': instance.outputPath,
      'format': _$VideoFormatEnumMap[instance.format]!,
      'resolution': _$ResolutionEnumMap[instance.resolution]!,
      'quality': _$QualityEnumMap[instance.quality]!,
      'frameRate': instance.frameRate,
      'videoPreset': instance.videoPreset,
      'audioSettings': instance.audioSettings,
    };

const _$VideoFormatEnumMap = {VideoFormat.mp4: 'mp4', VideoFormat.mov: 'mov'};

const _$ResolutionEnumMap = {
  Resolution.r480p: 'r480p',
  Resolution.r720p: 'r720p',
  Resolution.r1080p: 'r1080p',
  Resolution.r4k: 'r4k',
};

const _$QualityEnumMap = {
  Quality.low: 'low',
  Quality.standard: 'standard',
  Quality.high: 'high',
};

AudioSettings _$AudioSettingsFromJson(Map<String, dynamic> json) =>
    AudioSettings(
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 44100,
      bitrate: (json['bitrate'] as num?)?.toInt() ?? 128000,
      channels: (json['channels'] as num?)?.toInt() ?? 2,
      codec: json['codec'] as String? ?? 'aac',
    );

Map<String, dynamic> _$AudioSettingsToJson(AudioSettings instance) =>
    <String, dynamic>{
      'sampleRate': instance.sampleRate,
      'bitrate': instance.bitrate,
      'channels': instance.channels,
      'codec': instance.codec,
    };
