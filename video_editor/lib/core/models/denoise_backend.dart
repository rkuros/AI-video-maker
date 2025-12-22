/// Backend used to execute denoise processing.
///
/// - `ffmpeg`: CPU FFmpeg filters (portable).
/// - `coreImage`: macOS/iOS Core Image (GPU) spatial denoise.
/// - `coreML`: Core ML (GPU/NPU) model-based denoise (offline/pre-render).
enum DenoiseBackend {
  ffmpeg,
  coreImage,
  coreML,
}

extension DenoiseBackendX on DenoiseBackend {
  String get displayName {
    switch (this) {
      case DenoiseBackend.ffmpeg:
        return 'FFmpeg (CPU)';
      case DenoiseBackend.coreImage:
        return 'Core Image (GPU)';
      case DenoiseBackend.coreML:
        return 'Core ML (NPU/GPU)';
    }
  }
}

