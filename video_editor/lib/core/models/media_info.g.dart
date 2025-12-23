// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VideoInfo _$VideoInfoFromJson(Map<String, dynamic> json) => VideoInfo(
  resolution: $enumDecode(_$ResolutionEnumMap, json['resolution']),
  frameRate: (json['frameRate'] as num).toInt(),
  duration: Duration(microseconds: (json['duration'] as num).toInt()),
  codec: json['codec'] as String,
  bitrate: (json['bitrate'] as num).toInt(),
);

Map<String, dynamic> _$VideoInfoToJson(VideoInfo instance) => <String, dynamic>{
  'resolution': _$ResolutionEnumMap[instance.resolution]!,
  'frameRate': instance.frameRate,
  'duration': instance.duration.inMicroseconds,
  'codec': instance.codec,
  'bitrate': instance.bitrate,
};

const _$ResolutionEnumMap = {
  Resolution.r480p: 'r480p',
  Resolution.r720p: 'r720p',
  Resolution.r1080p: 'r1080p',
  Resolution.r4k: 'r4k',
};

AudioInfo _$AudioInfoFromJson(Map<String, dynamic> json) => AudioInfo(
  sampleRate: (json['sampleRate'] as num).toInt(),
  channels: (json['channels'] as num).toInt(),
  duration: Duration(microseconds: (json['duration'] as num).toInt()),
  codec: json['codec'] as String,
  bitrate: (json['bitrate'] as num).toInt(),
);

Map<String, dynamic> _$AudioInfoToJson(AudioInfo instance) => <String, dynamic>{
  'sampleRate': instance.sampleRate,
  'channels': instance.channels,
  'duration': instance.duration.inMicroseconds,
  'codec': instance.codec,
  'bitrate': instance.bitrate,
};

DenoiseSettings _$DenoiseSettingsFromJson(Map<String, dynamic> json) =>
    DenoiseSettings(
      strength: (json['strength'] as num?)?.toDouble() ?? 0.5,
      temporalRadius: (json['temporalRadius'] as num?)?.toInt() ?? 3,
      lumaStrength: (json['lumaStrength'] as num?)?.toDouble() ?? 0.7,
      chromaStrength: (json['chromaStrength'] as num?)?.toDouble() ?? 0.5,
      preserveDetails: json['preserveDetails'] as bool? ?? true,
      level:
          $enumDecodeNullable(_$DenoiseLevelEnumMap, json['level']) ??
          DenoiseLevel.balanced,
      backend:
          $enumDecodeNullable(_$DenoiseBackendEnumMap, json['backend']) ??
          DenoiseBackend.ffmpeg,
      useNlmeans: json['useNlmeans'] as bool? ?? false,
      useBm3d: json['useBm3d'] as bool? ?? false,
      useVaguedenoiser: json['useVaguedenoiser'] as bool? ?? false,
      useDctdnoiz: json['useDctdnoiz'] as bool? ?? false,
      useAiModel: json['useAiModel'] as bool? ?? false,
      nlmeansStrength: (json['nlmeansStrength'] as num?)?.toDouble() ?? 0.7,
      nlmeansPatchSize: (json['nlmeansPatchSize'] as num?)?.toInt() ?? 7,
      nlmeansResearchSize: (json['nlmeansResearchSize'] as num?)?.toInt() ?? 15,
      bm3dSigma: (json['bm3dSigma'] as num?)?.toDouble() ?? 3.0,
      aiModelPath: json['aiModelPath'] as String?,
    );

Map<String, dynamic> _$DenoiseSettingsToJson(DenoiseSettings instance) =>
    <String, dynamic>{
      'strength': instance.strength,
      'temporalRadius': instance.temporalRadius,
      'lumaStrength': instance.lumaStrength,
      'chromaStrength': instance.chromaStrength,
      'preserveDetails': instance.preserveDetails,
      'level': _$DenoiseLevelEnumMap[instance.level]!,
      'backend': _$DenoiseBackendEnumMap[instance.backend]!,
      'useNlmeans': instance.useNlmeans,
      'useBm3d': instance.useBm3d,
      'useVaguedenoiser': instance.useVaguedenoiser,
      'useDctdnoiz': instance.useDctdnoiz,
      'useAiModel': instance.useAiModel,
      'nlmeansStrength': instance.nlmeansStrength,
      'nlmeansPatchSize': instance.nlmeansPatchSize,
      'nlmeansResearchSize': instance.nlmeansResearchSize,
      'bm3dSigma': instance.bm3dSigma,
      'aiModelPath': instance.aiModelPath,
    };

const _$DenoiseLevelEnumMap = {
  DenoiseLevel.fast: 'fast',
  DenoiseLevel.balanced: 'balanced',
  DenoiseLevel.high: 'high',
  DenoiseLevel.maximum: 'maximum',
  DenoiseLevel.aiEnhanced: 'aiEnhanced',
};

const _$DenoiseBackendEnumMap = {
  DenoiseBackend.ffmpeg: 'ffmpeg',
  DenoiseBackend.coreImage: 'coreImage',
  DenoiseBackend.coreML: 'coreML',
};
