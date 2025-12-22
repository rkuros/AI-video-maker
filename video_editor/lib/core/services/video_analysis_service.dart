import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/models/denoise_level.dart';

/// Service for analyzing video content to determine optimal denoise settings
class VideoAnalysisService {
  static const _ffmpeg = 'ffmpeg';
  static const _ffprobe = 'ffprobe';

  /// Analyze video to determine characteristics for denoising
  Future<VideoAnalysisResult> analyzeVideo(String filePath) async {
    // Get video metadata
    final metadata = await _getVideoMetadata(filePath);
    final duration = metadata['duration'] as double? ?? 0.0;

    if (duration <= 0) {
      throw Exception('Invalid video duration');
    }

    // Sample 3 frames: beginning (1s), middle, end (-1s)
    final sampleTimes = [
      1.0,
      duration / 2,
      max(1.0, duration - 1.0),
    ];

    final frameStats = <_FrameStats>[];
    for (final time in sampleTimes) {
      final stats = await _analyzeFrame(filePath, time);
      frameStats.add(stats);
    }

    // Calculate averages
    final avgBrightness = frameStats
        .map((s) => s.brightness)
        .reduce((a, b) => a + b) / frameStats.length;

    final avgNoiseLevel = frameStats
        .map((s) => s.noiseLevel)
        .reduce((a, b) => a + b) / frameStats.length;

    final avgMotion = frameStats
        .map((s) => s.motionEstimate)
        .reduce((a, b) => a + b) / frameStats.length;

    final avgComplexity = frameStats
        .map((s) => s.complexity)
        .reduce((a, b) => a + b) / frameStats.length;

    return VideoAnalysisResult(
      averageBrightness: avgBrightness,
      noiseLevel: avgNoiseLevel,
      motionLevel: avgMotion,
      sceneComplexity: avgComplexity,
      isDarkVideo: avgBrightness < 0.3,
      isVeryDarkVideo: avgBrightness < 0.15,
      isNoisyVideo: avgNoiseLevel > 0.4,
    );
  }

  /// Recommend denoise settings based on analysis result
  DenoiseSettings recommendSettings(VideoAnalysisResult analysis) {
    // Determine denoise level based on darkness and noise
    DenoiseLevel level;

    if (analysis.isVeryDarkVideo && analysis.isNoisyVideo) {
      // Very dark and noisy - need maximum denoising
      level = DenoiseLevel.maximum;
    } else if (analysis.isDarkVideo && analysis.isNoisyVideo) {
      // Dark and noisy - need high denoising
      level = DenoiseLevel.high;
    } else if (analysis.isDarkVideo || analysis.isNoisyVideo) {
      // Either dark or noisy - balanced denoising
      level = DenoiseLevel.balanced;
    } else {
      // Not particularly dark or noisy - light denoising
      level = DenoiseLevel.fast;
    }

    // Calculate strength based on noise level
    final strength = (analysis.noiseLevel * 0.8 + 0.2).clamp(0.0, 1.0);

    // Temporal radius based on motion level (less motion = more temporal filtering)
    final temporalRadius = (5 - (analysis.motionLevel * 3)).round().clamp(1, 5);

    // Luma strength based on brightness (darker = more luma denoising)
    final lumaStrength = (1.0 - analysis.averageBrightness * 0.5).clamp(0.5, 1.0);

    // Chroma strength based on noise level
    final chromaStrength = (analysis.noiseLevel * 0.8 + 0.3).clamp(0.3, 1.0);

    // Determine which filters to use based on level
    // CRITICAL: nlmeans and bm3d are EXTREMELY slow (CPU-only, no GPU/NPU support)
    // For practical use, we ONLY use hqdn3d (fast, temporal+spatial, good quality)
    // - fast: light hqdn3d settings (real-time capable)
    // - balanced: moderate hqdn3d settings
    // - high: strong hqdn3d settings
    // - maximum: very strong hqdn3d settings
    final useNlmeans = false;  // Disabled - too slow (0.3fps)
    final useBm3d = false;     // Disabled - extremely slow
    final useVaguedenoiser = false;  // Disabled - not worth the cost
    final useDctdnoiz = false;       // Disabled - not worth the cost

    // Adjust hqdn3d strength based on level for practical performance
    final adjustedLumaStrength = lumaStrength * (0.7 + level.index * 0.15);
    final adjustedChromaStrength = chromaStrength * (0.7 + level.index * 0.15);
    final adjustedTemporalRadius = min(5, temporalRadius + level.index);

    return DenoiseSettings(
      strength: strength,
      temporalRadius: adjustedTemporalRadius,
      lumaStrength: adjustedLumaStrength.clamp(0.5, 1.0),
      chromaStrength: adjustedChromaStrength.clamp(0.3, 1.0),
      preserveDetails: true,
      level: level,
      useNlmeans: useNlmeans,
      useBm3d: useBm3d,
      useVaguedenoiser: useVaguedenoiser,
      useDctdnoiz: useDctdnoiz,
      useAiModel: false,
      nlmeansStrength: 0.5,  // Unused but needs a value
      nlmeansPatchSize: 5,    // Unused but needs a value
      nlmeansResearchSize: 11, // Unused but needs a value
      bm3dSigma: 3.0,         // Unused but needs a value
    );
  }

  Future<Map<String, dynamic>> _getVideoMetadata(String filePath) async {
    final result = await Process.run(_ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'json',
      filePath,
    ]);

    if (result.exitCode != 0) {
      throw Exception('Failed to get video metadata: ${result.stderr}');
    }

    final data = json.decode(result.stdout as String) as Map<String, dynamic>;
    final format = data['format'] as Map<String, dynamic>?;
    final durationStr = format?['duration'] as String?;
    final duration = double.tryParse(durationStr ?? '0') ?? 0.0;

    return {'duration': duration};
  }

  Future<_FrameStats> _analyzeFrame(String filePath, double timestamp) async {
    // Extract frame as raw pixel data
    final process = await Process.start(_ffmpeg, [
      '-ss',
      timestamp.toStringAsFixed(3),
      '-i',
      filePath,
      '-vframes',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'gray',
      '-s',
      '320x180', // Small size for fast analysis
      '-',
    ]);

    final bytes = <int>[];
    await process.stdout.forEach(bytes.addAll);
    await process.stderr.drain();
    final exitCode = await process.exitCode;

    if (exitCode != 0 || bytes.isEmpty) {
      // If frame extraction fails, return default stats
      return _FrameStats(
        brightness: 0.5,
        noiseLevel: 0.3,
        motionEstimate: 0.5,
        complexity: 0.5,
      );
    }

    // Calculate brightness (average pixel value)
    final sum = bytes.reduce((a, b) => a + b);
    final brightness = (sum / bytes.length) / 255.0;

    // Calculate noise level (standard deviation as proxy for noise)
    final mean = sum / bytes.length;
    var variance = 0.0;
    for (final byte in bytes) {
      final diff = byte - mean;
      variance += diff * diff;
    }
    variance /= bytes.length;
    final stdDev = sqrt(variance);
    final noiseLevel = (stdDev / 128.0).clamp(0.0, 1.0);

    // Calculate complexity (high frequency content)
    var edgeSum = 0.0;
    const width = 320;
    for (var i = 0; i < bytes.length - width - 1; i++) {
      final hDiff = (bytes[i + 1] - bytes[i]).abs();
      final vDiff = (bytes[i + width] - bytes[i]).abs();
      edgeSum += hDiff + vDiff;
    }
    final complexity = (edgeSum / (bytes.length * 255 * 2)).clamp(0.0, 1.0);

    // Motion estimate (for now, use complexity as proxy)
    // In future, could compare consecutive frames
    final motionEstimate = complexity;

    return _FrameStats(
      brightness: brightness,
      noiseLevel: noiseLevel,
      motionEstimate: motionEstimate,
      complexity: complexity,
    );
  }
}

/// Result of video analysis
class VideoAnalysisResult {
  /// Average brightness level (0.0 - 1.0)
  final double averageBrightness;

  /// Estimated noise level (0.0 - 1.0)
  final double noiseLevel;

  /// Estimated motion level (0.0 - 1.0)
  final double motionLevel;

  /// Scene complexity (0.0 - 1.0)
  final double sceneComplexity;

  /// Whether the video is considered dark (brightness < 0.3)
  final bool isDarkVideo;

  /// Whether the video is very dark (brightness < 0.15)
  final bool isVeryDarkVideo;

  /// Whether the video is noisy (noiseLevel > 0.4)
  final bool isNoisyVideo;

  const VideoAnalysisResult({
    required this.averageBrightness,
    required this.noiseLevel,
    required this.motionLevel,
    required this.sceneComplexity,
    required this.isDarkVideo,
    required this.isVeryDarkVideo,
    required this.isNoisyVideo,
  });
}

class _FrameStats {
  final double brightness;
  final double noiseLevel;
  final double motionEstimate;
  final double complexity;

  _FrameStats({
    required this.brightness,
    required this.noiseLevel,
    required this.motionEstimate,
    required this.complexity,
  });
}
