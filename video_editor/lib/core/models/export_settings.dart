import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'export_settings.g.dart';

/// Settings for exporting the video
@JsonSerializable()
class ExportSettings {
  final String outputPath;
  final VideoFormat format;
  final Resolution resolution;
  final Quality quality;
  final int frameRate;
  final String videoPreset;
  final AudioSettings audioSettings;
  final bool audioNormalizeEnabled;
  final String audioNormalizeFilter;

  ExportSettings({
    this.outputPath = '',
    this.format = VideoFormat.mp4,
    this.resolution = Resolution.r1080p,
    this.quality = Quality.high,
    this.frameRate = 30,
    this.videoPreset = 'medium',
    AudioSettings? audioSettings,
    this.audioNormalizeEnabled = false,
    this.audioNormalizeFilter = 'dynaudnorm',
  }) : audioSettings = audioSettings ?? AudioSettings();

  factory ExportSettings.fromJson(Map<String, dynamic> json) =>
      _$ExportSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$ExportSettingsToJson(this);

  ExportSettings copyWith({
    String? outputPath,
    VideoFormat? format,
    Resolution? resolution,
    Quality? quality,
    int? frameRate,
    String? videoPreset,
    AudioSettings? audioSettings,
    bool? audioNormalizeEnabled,
    String? audioNormalizeFilter,
  }) {
    return ExportSettings(
      outputPath: outputPath ?? this.outputPath,
      format: format ?? this.format,
      resolution: resolution ?? this.resolution,
      quality: quality ?? this.quality,
      frameRate: frameRate ?? this.frameRate,
      videoPreset: videoPreset ?? this.videoPreset,
      audioSettings: audioSettings ?? this.audioSettings,
      audioNormalizeEnabled:
          audioNormalizeEnabled ?? this.audioNormalizeEnabled,
      audioNormalizeFilter: audioNormalizeFilter ?? this.audioNormalizeFilter,
    );
  }
}

/// Audio settings for export
@JsonSerializable()
class AudioSettings {
  final int sampleRate;
  final int bitrate;
  final int channels;
  final String codec;

  const AudioSettings({
    this.sampleRate = 44100,
    this.bitrate = 128000,
    this.channels = 2,
    this.codec = 'aac',
  });

  factory AudioSettings.fromJson(Map<String, dynamic> json) =>
      _$AudioSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$AudioSettingsToJson(this);

  AudioSettings copyWith({
    int? sampleRate,
    int? bitrate,
    int? channels,
    String? codec,
  }) {
    return AudioSettings(
      sampleRate: sampleRate ?? this.sampleRate,
      bitrate: bitrate ?? this.bitrate,
      channels: channels ?? this.channels,
      codec: codec ?? this.codec,
    );
  }
}
