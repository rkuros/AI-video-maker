import 'dart:typed_data';
import 'package:video_editor/core/models/models.dart';

/// Abstract interface for video processing engine
abstract class VideoEngine {
  /// Load a video file
  Future<void> loadVideo(String filePath);

  /// Get video information from a file
  Future<VideoInfo> getVideoInfo(String filePath);

  /// Get audio information from a file
  Future<AudioInfo> getAudioInfo(String filePath);

  /// Generate a thumbnail at a specific timestamp
  Future<Uint8List> generateThumbnail(
    String filePath,
    Duration timestamp, {
    int width = 320,
    int height = 180,
  });

  /// Apply an effect to a video
  Future<void> applyEffect(
    String inputPath,
    String outputPath,
    Effect effect,
  );

  /// Apply denoise filter to video
  Future<void> applyDenoise(
    String inputPath,
    String outputPath,
    DenoiseSettings settings,
  );

  /// Extract audio waveform data
  Future<List<double>> extractWaveform(
    String audioPath, {
    int sampleCount = 1000,
  });

  /// Dispose resources
  Future<void> dispose();
}
