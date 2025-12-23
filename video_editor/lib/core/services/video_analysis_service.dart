import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/models/denoise_level.dart';

/// Service for analyzing video content to determine optimal denoise settings
class VideoAnalysisService {
  static const _ffmpeg = 'ffmpeg';
  static const _ffprobe = 'ffprobe';
  static const _analysisWidth = 320;
  static const _analysisHeight = 180;
  static const _motionDeltaSeconds = 0.25;

  /// Analyze video to determine characteristics for denoising
  Future<VideoAnalysisResult> analyzeVideo(String filePath) async {
    // Get video metadata
    final metadata = await _getVideoMetadata(filePath);
    final duration = metadata['duration'] as double? ?? 0.0;

    if (duration <= 0) {
      throw Exception('Invalid video duration');
    }

    // Sample a few frames across the timeline.
    // Keep this small because each sample invokes ffmpeg.
    final sampleTimes = _buildSampleTimes(duration);

    final frameStats = <_FrameStats>[];
    for (final time in sampleTimes) {
      final nextTime = min(duration - 0.1, time + _motionDeltaSeconds);
      final stats = await _analyzeFrame(
        filePath,
        time,
        nextTimestamp: nextTime,
      );
      frameStats.add(stats);
    }

    // Calculate averages
    final avgBrightness =
        frameStats.map((s) => s.brightness).reduce((a, b) => a + b) /
        frameStats.length;

    final avgNoiseLevel =
        frameStats.map((s) => s.noiseLevel).reduce((a, b) => a + b) /
        frameStats.length;

    final avgMotion =
        frameStats.map((s) => s.motionEstimate).reduce((a, b) => a + b) /
        frameStats.length;

    final avgComplexity =
        frameStats.map((s) => s.complexity).reduce((a, b) => a + b) /
        frameStats.length;

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
    // Keep recommendations in the "simple UI" band: Fast/Balanced/High.
    // (Avoid recommending Maximum/AI Enhanced because those imply very slow filters/export-only flows.)
    final brightness = analysis.averageBrightness.clamp(0.0, 1.0).toDouble();
    final noise = analysis.noiseLevel.clamp(0.0, 1.0).toDouble();
    final motion = analysis.motionLevel.clamp(0.0, 1.0).toDouble();

    DenoiseLevel level;
    if (noise > 0.60 || (brightness < 0.20 && noise > 0.45)) {
      level = DenoiseLevel.high;
    } else if (noise > 0.35 || brightness < 0.30) {
      level = DenoiseLevel.balanced;
    } else {
      level = DenoiseLevel.fast;
    }

    // Strength: start gentle to preserve detail, scale with estimated noise.
    final strength = (0.15 + noise * 0.75).clamp(0.0, 0.9).toDouble();

    // Temporal radius: more motion => less temporal smoothing (reduce ghosting).
    final temporalRadius = (4.5 - motion * 3.0).round().clamp(1, 5);

    // Luma/chroma: bias luma more for dark footage and chroma more for high noise.
    final lumaStrength = (0.55 + (1.0 - brightness) * 0.45)
        .clamp(0.5, 1.0)
        .toDouble();
    final chromaStrength = (0.35 + noise * 0.65).clamp(0.3, 1.0).toDouble();

    // Determine which filters to use based on level
    // CRITICAL: nlmeans and bm3d are EXTREMELY slow (CPU-only, no GPU/NPU support)
    // For practical use, we ONLY use hqdn3d (fast, temporal+spatial, good quality)
    // - fast: light hqdn3d settings (real-time capable)
    // - balanced: moderate hqdn3d settings
    // - high: strong hqdn3d settings
    // - maximum: very strong hqdn3d settings
    final useNlmeans = false; // Disabled - too slow (0.3fps)
    final useBm3d = false; // Disabled - extremely slow
    final useVaguedenoiser = false; // Disabled - not worth the cost
    final useDctdnoiz = false; // Disabled - not worth the cost

    // Adjust hqdn3d strength based on level for practical performance
    final levelFactor = switch (level) {
      DenoiseLevel.fast => 0.85,
      DenoiseLevel.balanced => 1.00,
      DenoiseLevel.high => 1.15,
      _ => 1.00,
    };
    final adjustedLumaStrength = (lumaStrength * levelFactor)
        .clamp(0.5, 1.0)
        .toDouble();
    final adjustedChromaStrength = (chromaStrength * levelFactor)
        .clamp(0.3, 1.0)
        .toDouble();
    final adjustedTemporalRadius = min(
      5,
      temporalRadius + (level == DenoiseLevel.high ? 1 : 0),
    ).clamp(1, 5).toInt();

    return DenoiseSettings(
      strength: strength,
      temporalRadius: adjustedTemporalRadius,
      lumaStrength: adjustedLumaStrength,
      chromaStrength: adjustedChromaStrength,
      preserveDetails: true,
      level: level,
      useNlmeans: useNlmeans,
      useBm3d: useBm3d,
      useVaguedenoiser: useVaguedenoiser,
      useDctdnoiz: useDctdnoiz,
      useAiModel: false,
      nlmeansStrength: 0.5, // Unused but needs a value
      nlmeansPatchSize: 5, // Unused but needs a value
      nlmeansResearchSize: 11, // Unused but needs a value
      bm3dSigma: 3.0, // Unused but needs a value
    );
  }

  List<double> _buildSampleTimes(double duration) {
    final safeStart = min(1.0, max(0.0, duration * 0.1)).toDouble();
    final safeEnd = max(0.1, duration - 1.0).toDouble();

    final candidates = <double>[
      safeStart,
      duration * 0.25,
      duration * 0.50,
      duration * 0.75,
      safeEnd,
    ].map((t) => t.clamp(0.0, max(0.0, duration - 0.1)).toDouble()).toList();

    // De-dup and keep stable ordering for very short clips.
    final unique = <double>[];
    for (final t in candidates) {
      if (unique.any((u) => (u - t).abs() < 0.01)) continue;
      unique.add(t);
    }

    // For short clips, 3 samples is enough.
    if (duration < 4.0 && unique.length > 3) {
      return [unique.first, unique[unique.length ~/ 2], unique.last];
    }

    return unique;
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

  Future<_FrameStats> _analyzeFrame(
    String filePath,
    double timestamp, {
    required double nextTimestamp,
  }) async {
    final bytes = await _extractGrayFrameBytes(filePath, timestamp);
    if (bytes == null || bytes.isEmpty) {
      return _FrameStats(
        brightness: 0.5,
        noiseLevel: 0.3,
        motionEstimate: 0.5,
        complexity: 0.5,
      );
    }

    final nextBytes = await _extractGrayFrameBytes(filePath, nextTimestamp);

    final brightness = _estimateBrightness(bytes);
    final complexity = _estimateComplexity(bytes);
    final noiseLevel = _estimateNoise(bytes);
    final motionEstimate = nextBytes == null
        ? complexity
        : _estimateMotion(bytes, nextBytes);

    return _FrameStats(
      brightness: brightness,
      noiseLevel: noiseLevel,
      motionEstimate: motionEstimate,
      complexity: complexity,
    );
  }

  Future<List<int>?> _extractGrayFrameBytes(
    String filePath,
    double timestamp,
  ) async {
    final baseArgs = <String>[
      if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
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
      '${_analysisWidth}x$_analysisHeight',
      '-',
    ];

    Future<ProcessResult> run(List<String> args) {
      return Process.run(
        _ffmpeg,
        args,
        stdoutEncoding: null,
        stderrEncoding: null,
      );
    }

    var result = await run(baseArgs);
    if (result.exitCode != 0 && Platform.isMacOS) {
      final fallbackArgs = baseArgs
          .where((a) => a != 'videotoolbox' && a != '-hwaccel')
          .toList();
      result = await run(fallbackArgs);
    }

    if (result.exitCode != 0 || result.stdout is! List<int>) {
      return null;
    }

    final bytes = result.stdout as List<int>;
    if (bytes.length != _analysisWidth * _analysisHeight) return null;
    return bytes;
  }

  double _estimateBrightness(List<int> bytes) {
    var sum = 0;
    for (final b in bytes) {
      sum += b;
    }
    return (sum / bytes.length) / 255.0;
  }

  double _estimateComplexity(List<int> bytes) {
    var edgeSum = 0.0;
    const width = _analysisWidth;
    for (var i = 0; i < bytes.length - width - 1; i++) {
      final hDiff = (bytes[i + 1] - bytes[i]).abs();
      final vDiff = (bytes[i + width] - bytes[i]).abs();
      edgeSum += hDiff + vDiff;
    }
    return (edgeSum / (bytes.length * 255 * 2)).clamp(0.0, 1.0);
  }

  double _estimateNoise(List<int> bytes) {
    // Estimate noise as the standard deviation of high-frequency residual.
    // This avoids interpreting edges/texture as "noise" as much as raw stddev does.
    const width = _analysisWidth;
    const height = _analysisHeight;

    var sumResidual = 0.0;
    var sumResidualSq = 0.0;
    var count = 0;

    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        final idx = row + x;

        // 3x3 box blur mean (integer math to keep it cheap).
        var localSum = 0;
        localSum += bytes[idx - width - 1];
        localSum += bytes[idx - width];
        localSum += bytes[idx - width + 1];
        localSum += bytes[idx - 1];
        localSum += bytes[idx];
        localSum += bytes[idx + 1];
        localSum += bytes[idx + width - 1];
        localSum += bytes[idx + width];
        localSum += bytes[idx + width + 1];
        final localMean = localSum / 9.0;

        final residual = bytes[idx] - localMean;
        sumResidual += residual;
        sumResidualSq += residual * residual;
        count++;
      }
    }

    if (count <= 0) return 0.0;

    final mean = sumResidual / count;
    final variance = max(0.0, (sumResidualSq / count) - (mean * mean));
    final stdDev = sqrt(variance);

    // Empirical scaling: residual stddev of ~20-30 corresponds to moderate noise.
    return (stdDev / 50.0).clamp(0.0, 1.0);
  }

  double _estimateMotion(List<int> a, List<int> b) {
    final len = min(a.length, b.length);
    if (len == 0) return 0.0;

    var diffSum = 0.0;
    for (var i = 0; i < len; i++) {
      diffSum += (a[i] - b[i]).abs();
    }
    return (diffSum / (len * 255.0)).clamp(0.0, 1.0);
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
