import 'dart:io';
import 'package:video_editor/core/models/highlight.dart';
import 'package:video_editor/core/services/highlight_feature_cache.dart';
import 'visual_feature_extractor.dart';
import 'audio_feature_extractor.dart';
import 'text_feature_extractor.dart';

/// Service for scoring video segments using multimodal features
class MultimodalFeatureScorer {
  final VisualFeatureExtractor _visualExtractor = VisualFeatureExtractor();
  final AudioFeatureExtractor _audioExtractor = AudioFeatureExtractor();
  final TextFeatureExtractor _textExtractor = TextFeatureExtractor();

  List<String> _selectEvenlySpacedFrames(List<String> frames, int targetCount) {
    if (targetCount <= 0 || frames.isEmpty) return const [];
    if (frames.length <= targetCount) return frames;
    final selected = <String>[];
    for (var i = 0; i < targetCount; i++) {
      final idx = ((i * frames.length) / targetCount).floor();
      selected.add(frames[idx]);
    }
    return selected;
  }

  /// Extract all features from a video segment
  Future<SegmentFeatures> extractFeatures(
    String videoPath,
    Duration startTime,
    Duration endTime,
  ) async {
    final segmentDuration = endTime - startTime;

    String? key;
    try {
      final stat = await File(videoPath).stat();
      key = HighlightFeatureCache.instance.buildKey(
        videoPath: videoPath,
        fileMtime: stat.modified,
        fileSize: stat.size,
        startTime: startTime,
        endTime: endTime,
        params: const <String, Object?>{
          'framesMotion': 10,
          'framesFace': 5,
          'framesAesthetic': 5,
          'framesOcr': 15,
          'audioSamplePoints': 10,
          'audioNormalize': AudioFeatureExtractor.analysisNormalizeFilter,
        },
      );
      final cached = await HighlightFeatureCache.instance.getFeatures(key);
      if (cached != null) return cached;
    } catch (_) {
      key = null;
    }

    // Extract frames once per segment and reuse to avoid re-running FFmpeg.
    final frames15 = await _visualExtractor.extractFrames(
      videoPath,
      segmentDuration,
      startTime: startTime,
      maxFrames: 15,
    );
    final frames10 = _selectEvenlySpacedFrames(frames15, 10);
    final frames5 = _selectEvenlySpacedFrames(frames15, 5);

    try {
      final sceneChangesFuture = _visualExtractor.detectSceneChanges(
        videoPath,
        segmentDuration,
        startTime: startTime,
      );
      final audioFuture = _audioExtractor.analyzeHighlightAudio(
        videoPath,
        segmentDuration,
        startTime: startTime,
        samplePoints: 10,
      );

      final motionFuture = _visualExtractor.analyzeMotion(
        videoPath,
        segmentDuration,
        startTime: startTime,
        samplePoints: 10,
        frames: frames10,
      );
      final aestheticFuture = _visualExtractor.analyzeAesthetics(
        videoPath,
        segmentDuration,
        startTime: startTime,
        samplePoints: 5,
        frames: frames5,
      );
      final faceSegments = await _visualExtractor.detectFaces(
        videoPath,
        segmentDuration,
        startTime: startTime,
        samplePoints: 5,
        frames: frames5,
      );

      // Extract text features
      final textSegments = await _textExtractor.extractTextFromVideo(
        videoPath,
        segmentDuration,
        startTime: startTime,
        samplePoints: 15,
        frames: frames15,
        cleanupFrames: false,
      );
      final keywordSegments = await _textExtractor
          .analyzeKeywordsFromTextSegments(textSegments);

      final motionSegments = await motionFuture;
      final aestheticSegments = await aestheticFuture;
      final sceneChanges = await sceneChangesFuture;
      final audio = await audioFuture;

      final features = SegmentFeatures(
        motionIntensity: _averageMotion(motionSegments),
        sceneChanges: sceneChanges.length,
        faceCount: _averageFaceCount(faceSegments),
        hasSmiles: faceSegments.any((f) => f.hasSmile),
        aestheticScore: _averageAesthetic(aestheticSegments),
        volumeLevel: _averageVolume(audio.volumeSegments),
        energyLevel: _averageEnergy(audio.energySegments),
        hasSpeech: audio.speechSegments.isNotEmpty,
        beatCount: audio.beats.length,
        hasText: textSegments.isNotEmpty,
        keywordScore: _averageKeywordScore(keywordSegments),
      );
      if (key != null) {
        await HighlightFeatureCache.instance.putFeatures(key, features);
      }
      return features;
    } finally {
      for (final framePath in frames15) {
        try {
          await File(framePath).delete();
        } catch (_) {}
      }
    }
  }

  /// Calculate comprehensive score for a segment
  Future<double> scoreSegment(
    String videoPath,
    Duration startTime,
    Duration endTime,
    HighlightPattern pattern,
  ) async {
    final features = await extractFeatures(videoPath, startTime, endTime);
    return _calculateScore(features, pattern);
  }

  /// Calculate score based on features and pattern
  double _calculateScore(SegmentFeatures features, HighlightPattern pattern) {
    // Get pattern-specific weights
    final weights = _getPatternWeights(pattern);

    // Visual component
    final visualScore = _calculateVisualScore(features, weights);

    // Audio component
    final audioScore = _calculateAudioScore(features, weights);

    // Text component
    final textScore = _calculateTextScore(features, weights);

    // Combine scores with pattern-specific overall weights
    return (visualScore * weights.visualWeight +
        audioScore * weights.audioWeight +
        textScore * weights.textWeight);
  }

  /// Calculate visual component score
  double _calculateVisualScore(
    SegmentFeatures features,
    PatternWeights weights,
  ) {
    double score = 0.0;

    // Motion
    score += features.motionIntensity * weights.motionWeight;

    // Scene changes (diversity indicator)
    final sceneChangeScore = (features.sceneChanges / 3).clamp(0.0, 1.0);
    score += sceneChangeScore * weights.sceneChangeWeight;

    // Faces (human interest)
    final faceScore = features.faceCount > 0 ? 0.8 : 0.2;
    final smileBonus = features.hasSmiles ? 0.2 : 0.0;
    score += (faceScore + smileBonus) * weights.faceWeight;

    // Aesthetic quality
    score += features.aestheticScore * weights.aestheticWeight;

    return score.clamp(0.0, 1.0);
  }

  /// Calculate audio component score
  double _calculateAudioScore(
    SegmentFeatures features,
    PatternWeights weights,
  ) {
    double score = 0.0;

    // Volume level
    score += features.volumeLevel * weights.volumeWeight;

    // Energy/excitement
    score += features.energyLevel * weights.energyWeight;

    // Speech presence
    final speechScore = features.hasSpeech ? 0.8 : 0.3;
    score += speechScore * weights.speechWeight;

    // Beat/rhythm
    final beatScore = (features.beatCount / 4).clamp(0.0, 1.0);
    score += beatScore * weights.beatWeight;

    return score.clamp(0.0, 1.0);
  }

  /// Calculate text component score
  double _calculateTextScore(SegmentFeatures features, PatternWeights weights) {
    double score = 0.0;

    // Text presence
    final textPresenceScore = features.hasText ? 0.7 : 0.3;
    score += textPresenceScore * 0.4;

    // Keyword relevance
    score += features.keywordScore * 0.6;

    return score.clamp(0.0, 1.0);
  }

  /// Get pattern-specific weights
  PatternWeights _getPatternWeights(HighlightPattern pattern) {
    if (pattern.id == 'sports') {
      return PatternWeights(
        visualWeight: 0.5,
        audioWeight: 0.4,
        textWeight: 0.1,
        motionWeight: 0.5,
        sceneChangeWeight: 0.2,
        faceWeight: 0.1,
        aestheticWeight: 0.2,
        volumeWeight: 0.3,
        energyWeight: 0.5,
        speechWeight: 0.1,
        beatWeight: 0.1,
      );
    } else if (pattern.id == 'travel') {
      return PatternWeights(
        visualWeight: 0.6,
        audioWeight: 0.3,
        textWeight: 0.1,
        motionWeight: 0.3,
        sceneChangeWeight: 0.4,
        faceWeight: 0.1,
        aestheticWeight: 0.2,
        volumeWeight: 0.2,
        energyWeight: 0.4,
        speechWeight: 0.2,
        beatWeight: 0.2,
      );
    } else if (pattern.id == 'vlog') {
      return PatternWeights(
        visualWeight: 0.3,
        audioWeight: 0.4,
        textWeight: 0.3,
        motionWeight: 0.2,
        sceneChangeWeight: 0.2,
        faceWeight: 0.4,
        aestheticWeight: 0.2,
        volumeWeight: 0.2,
        energyWeight: 0.3,
        speechWeight: 0.5,
        beatWeight: 0.0,
      );
    } else if (pattern.id == 'gaming') {
      return PatternWeights(
        visualWeight: 0.4,
        audioWeight: 0.5,
        textWeight: 0.1,
        motionWeight: 0.4,
        sceneChangeWeight: 0.3,
        faceWeight: 0.1,
        aestheticWeight: 0.2,
        volumeWeight: 0.2,
        energyWeight: 0.5,
        speechWeight: 0.2,
        beatWeight: 0.1,
      );
    } else if (pattern.id == 'interview') {
      return PatternWeights(
        visualWeight: 0.2,
        audioWeight: 0.6,
        textWeight: 0.2,
        motionWeight: 0.1,
        sceneChangeWeight: 0.1,
        faceWeight: 0.6,
        aestheticWeight: 0.2,
        volumeWeight: 0.2,
        energyWeight: 0.2,
        speechWeight: 0.6,
        beatWeight: 0.0,
      );
    } else if (pattern.id == 'tutorial') {
      return PatternWeights(
        visualWeight: 0.3,
        audioWeight: 0.4,
        textWeight: 0.3,
        motionWeight: 0.2,
        sceneChangeWeight: 0.3,
        faceWeight: 0.2,
        aestheticWeight: 0.3,
        volumeWeight: 0.2,
        energyWeight: 0.2,
        speechWeight: 0.4,
        beatWeight: 0.2,
      );
    }

    // Default weights for unknown patterns
    return PatternWeights(
      visualWeight: 0.4,
      audioWeight: 0.4,
      textWeight: 0.2,
      motionWeight: 0.3,
      sceneChangeWeight: 0.3,
      faceWeight: 0.2,
      aestheticWeight: 0.2,
      volumeWeight: 0.3,
      energyWeight: 0.3,
      speechWeight: 0.2,
      beatWeight: 0.2,
    );
  }

  // Helper methods for averaging features
  double _averageMotion(List<MotionSegment> segments) {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.motionIntensity).reduce((a, b) => a + b) /
        segments.length;
  }

  double _averageFaceCount(List<FaceSegment> segments) {
    if (segments.isEmpty) return 0.0;
    final avgCount =
        segments.map((s) => s.faceCount).reduce((a, b) => a + b) /
        segments.length;
    return (avgCount / 5).clamp(0.0, 1.0); // Normalize assuming max 5 faces
  }

  double _averageAesthetic(List<AestheticSegment> segments) {
    if (segments.isEmpty) return 0.5;
    return segments.map((s) => s.aestheticScore).reduce((a, b) => a + b) /
        segments.length;
  }

  double _averageVolume(List<VolumeSegment> segments) {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.meanVolume).reduce((a, b) => a + b) /
        segments.length;
  }

  double _averageEnergy(List<EnergySegment> segments) {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.energy).reduce((a, b) => a + b) /
        segments.length;
  }

  double _averageKeywordScore(List<KeywordSegment> segments) {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.relevanceScore).reduce((a, b) => a + b) /
        segments.length;
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _visualExtractor.dispose();
    await _textExtractor.dispose();
  }
}

/// Extracted features from a video segment
class SegmentFeatures {
  final double motionIntensity;
  final int sceneChanges;
  final double faceCount;
  final bool hasSmiles;
  final double aestheticScore;
  final double volumeLevel;
  final double energyLevel;
  final bool hasSpeech;
  final int beatCount;
  final bool hasText;
  final double keywordScore;

  const SegmentFeatures({
    required this.motionIntensity,
    required this.sceneChanges,
    required this.faceCount,
    required this.hasSmiles,
    required this.aestheticScore,
    required this.volumeLevel,
    required this.energyLevel,
    required this.hasSpeech,
    required this.beatCount,
    required this.hasText,
    required this.keywordScore,
  });
}

/// Pattern-specific feature weights
class PatternWeights {
  // Overall component weights
  final double visualWeight;
  final double audioWeight;
  final double textWeight;

  // Visual feature weights
  final double motionWeight;
  final double sceneChangeWeight;
  final double faceWeight;
  final double aestheticWeight;

  // Audio feature weights
  final double volumeWeight;
  final double energyWeight;
  final double speechWeight;
  final double beatWeight;

  const PatternWeights({
    required this.visualWeight,
    required this.audioWeight,
    required this.textWeight,
    required this.motionWeight,
    required this.sceneChangeWeight,
    required this.faceWeight,
    required this.aestheticWeight,
    required this.volumeWeight,
    required this.energyWeight,
    required this.speechWeight,
    required this.beatWeight,
  });
}
