import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';
import 'denoise_level.dart';
import 'denoise_backend.dart';

part 'media_info.g.dart';

/// Video information extracted from a video file
@JsonSerializable()
class VideoInfo {
  final Resolution resolution;
  final int frameRate;
  final Duration duration;
  final String codec;
  final int bitrate;

  VideoInfo({
    required this.resolution,
    required this.frameRate,
    required this.duration,
    required this.codec,
    required this.bitrate,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) =>
      _$VideoInfoFromJson(json);

  Map<String, dynamic> toJson() => _$VideoInfoToJson(this);
}

/// Audio information extracted from an audio file
@JsonSerializable()
class AudioInfo {
  final int sampleRate;
  final int channels;
  final Duration duration;
  final String codec;
  final int bitrate;

  AudioInfo({
    required this.sampleRate,
    required this.channels,
    required this.duration,
    required this.codec,
    required this.bitrate,
  });

  factory AudioInfo.fromJson(Map<String, dynamic> json) =>
      _$AudioInfoFromJson(json);

  Map<String, dynamic> toJson() => _$AudioInfoToJson(this);
}

/// Denoise settings for low-light video processing
@JsonSerializable()
class DenoiseSettings {
  /// Overall denoise strength (0.0 - 1.0)
  final double strength;

  /// Number of frames to process in temporal direction (1 - 5)
  final int temporalRadius;

  /// Luma (brightness) component strength (0.0 - 1.0)
  final double lumaStrength;

  /// Chroma (color) component strength (0.0 - 1.0)
  final double chromaStrength;

  /// Whether to preserve fine details
  final bool preserveDetails;

  /// Denoise quality level
  final DenoiseLevel level;

  /// Backend used to execute denoise processing.
  final DenoiseBackend backend;

  /// Use nlmeans filter
  final bool useNlmeans;

  /// Use bm3d filter
  final bool useBm3d;

  /// Use vaguedenoiser filter
  final bool useVaguedenoiser;

  /// Use dctdnoiz filter
  final bool useDctdnoiz;

  /// Use AI model for denoising
  final bool useAiModel;

  /// nlmeans denoising strength (0.0 - 1.0)
  final double nlmeansStrength;

  /// nlmeans patch size (typically 7)
  final int nlmeansPatchSize;

  /// nlmeans research window size (typically 15)
  final int nlmeansResearchSize;

  /// bm3d sigma parameter (noise level estimation)
  final double bm3dSigma;

  /// Path to AI model file (optional)
  final String? aiModelPath;

  const DenoiseSettings({
    this.strength = 0.5,
    this.temporalRadius = 3,
    this.lumaStrength = 0.7,
    this.chromaStrength = 0.5,
    this.preserveDetails = true,
    this.level = DenoiseLevel.balanced,
    this.backend = DenoiseBackend.ffmpeg,
    this.useNlmeans = false,
    this.useBm3d = false,
    this.useVaguedenoiser = false,
    this.useDctdnoiz = false,
    this.useAiModel = false,
    this.nlmeansStrength = 0.7,
    this.nlmeansPatchSize = 7,
    this.nlmeansResearchSize = 15,
    this.bm3dSigma = 3.0,
    this.aiModelPath,
  });

  factory DenoiseSettings.fromJson(Map<String, dynamic> json) =>
      _$DenoiseSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$DenoiseSettingsToJson(this);

  DenoiseSettings copyWith({
    double? strength,
    int? temporalRadius,
    double? lumaStrength,
    double? chromaStrength,
    bool? preserveDetails,
    DenoiseLevel? level,
    DenoiseBackend? backend,
    bool? useNlmeans,
    bool? useBm3d,
    bool? useVaguedenoiser,
    bool? useDctdnoiz,
    bool? useAiModel,
    double? nlmeansStrength,
    int? nlmeansPatchSize,
    int? nlmeansResearchSize,
    double? bm3dSigma,
    String? aiModelPath,
  }) {
    return DenoiseSettings(
      strength: strength ?? this.strength,
      temporalRadius: temporalRadius ?? this.temporalRadius,
      lumaStrength: lumaStrength ?? this.lumaStrength,
      chromaStrength: chromaStrength ?? this.chromaStrength,
      preserveDetails: preserveDetails ?? this.preserveDetails,
      level: level ?? this.level,
      backend: backend ?? this.backend,
      useNlmeans: useNlmeans ?? this.useNlmeans,
      useBm3d: useBm3d ?? this.useBm3d,
      useVaguedenoiser: useVaguedenoiser ?? this.useVaguedenoiser,
      useDctdnoiz: useDctdnoiz ?? this.useDctdnoiz,
      useAiModel: useAiModel ?? this.useAiModel,
      nlmeansStrength: nlmeansStrength ?? this.nlmeansStrength,
      nlmeansPatchSize: nlmeansPatchSize ?? this.nlmeansPatchSize,
      nlmeansResearchSize: nlmeansResearchSize ?? this.nlmeansResearchSize,
      bm3dSigma: bm3dSigma ?? this.bm3dSigma,
      aiModelPath: aiModelPath ?? this.aiModelPath,
    );
  }
}
