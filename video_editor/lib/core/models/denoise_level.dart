/// Levels of video denoising quality
enum DenoiseLevel {
  /// Fast preview mode - hqdn3d only
  /// Processing time: ~1-2s for 10s 1080p clip
  fast,

  /// Balanced mode - hqdn3d + nlmeans
  /// Processing time: ~5-10s for 10s 1080p clip
  balanced,

  /// High quality mode - bm3d + nlmeans
  /// Processing time: ~20-40s for 10s 1080p clip
  high,

  /// Maximum quality mode - bm3d + nlmeans + vaguedenoiser
  /// Processing time: ~60-120s for 10s 1080p clip
  maximum,

  /// AI-enhanced mode - FFmpeg filters + AI model
  /// Processing time: ~5-15min for 10s 1080p clip (export only)
  aiEnhanced,
}

extension DenoiseLevelExtension on DenoiseLevel {
  String get displayName {
    switch (this) {
      case DenoiseLevel.fast:
        return 'Fast';
      case DenoiseLevel.balanced:
        return 'Balanced';
      case DenoiseLevel.high:
        return 'High';
      case DenoiseLevel.maximum:
        return 'Maximum';
      case DenoiseLevel.aiEnhanced:
        return 'AI Enhanced';
    }
  }

  String get description {
    switch (this) {
      case DenoiseLevel.fast:
        return 'Quick preview (hqdn3d only)';
      case DenoiseLevel.balanced:
        return 'Good quality, reasonable speed';
      case DenoiseLevel.high:
        return 'High quality, slower processing';
      case DenoiseLevel.maximum:
        return 'Maximum quality, slow processing';
      case DenoiseLevel.aiEnhanced:
        return 'AI-powered, highest quality (export only)';
    }
  }

  String get estimatedTime {
    switch (this) {
      case DenoiseLevel.fast:
        return 'Instant';
      case DenoiseLevel.balanced:
        return '2-5s';
      case DenoiseLevel.high:
        return '10-20s';
      case DenoiseLevel.maximum:
        return '30-60s';
      case DenoiseLevel.aiEnhanced:
        return '5-15min';
    }
  }

  bool get supportsPreview {
    switch (this) {
      case DenoiseLevel.fast:
      case DenoiseLevel.balanced:
        return true;
      case DenoiseLevel.high:
      case DenoiseLevel.maximum:
      case DenoiseLevel.aiEnhanced:
        return false;
    }
  }
}
