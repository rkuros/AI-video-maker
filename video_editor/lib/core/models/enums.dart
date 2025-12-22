/// Media types supported by the application
enum MediaType {
  video,
  audio,
  image,
}

/// Track types in the timeline
enum TrackType {
  video,
  audio,
}

/// Video output formats
enum VideoFormat {
  mp4,
  mov,
}

/// Export resolution options
enum Resolution {
  r480p(width: 854, height: 480),
  r720p(width: 1280, height: 720),
  r1080p(width: 1920, height: 1080),
  r4k(width: 3840, height: 2160);

  const Resolution({required this.width, required this.height});
  final int width;
  final int height;
}

/// Export quality settings
enum Quality {
  low,
  standard,
  high,
}

/// Timeline preview quality presets (render settings).
enum PreviewQualityPreset {
  draft,
  quick,
  balanced,
  standard,
}

extension PreviewQualityPresetX on PreviewQualityPreset {
  String get label {
    switch (this) {
      case PreviewQualityPreset.draft:
        return 'Draft (480p/12fps)';
      case PreviewQualityPreset.quick:
        return 'Quick (480p/15fps)';
      case PreviewQualityPreset.balanced:
        return 'Balanced (720p/24fps)';
      case PreviewQualityPreset.standard:
        return 'Standard (720p/30fps)';
    }
  }
}

/// Transition types
enum TransitionType {
  fadeIn,
  fadeOut,
  crossFade,
  wipe,
  slide,
  zoom,
}

/// Beat marker types
enum BeatType {
  strong,
  weak,
  accent,
}
