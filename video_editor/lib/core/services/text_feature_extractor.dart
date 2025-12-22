import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'visual_feature_extractor.dart';

/// Service for extracting text features from videos
class TextFeatureExtractor {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _visualExtractor = VisualFeatureExtractor();

  /// Extract text from video frames using OCR
  Future<List<TextSegment>> extractTextFromVideo(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 15,
  }) async {
    final textSegments = <TextSegment>[];

    // Extract frames for OCR
    final frames = await _visualExtractor.extractFrames(
      videoPath,
      videoDuration,
      startTime: startTime,
      maxFrames: samplePoints,
    );

    for (int i = 0; i < frames.length; i++) {
      final framePath = frames[i];
      final inputImage = InputImage.fromFilePath(framePath);

      try {
        final recognizedText = await _textRecognizer.processImage(inputImage);

        if (recognizedText.text.isNotEmpty) {
          final timestamp = Duration(
            milliseconds: (videoDuration.inMilliseconds * i / frames.length).round(),
          );

          // Extract all text blocks
          final textBlocks = recognizedText.blocks
              .map((block) => block.text)
              .where((text) => text.trim().isNotEmpty)
              .toList();

          if (textBlocks.isNotEmpty) {
            textSegments.add(TextSegment(
              timestamp: timestamp,
              text: recognizedText.text,
              textBlocks: textBlocks,
              confidence: _calculateAverageConfidence(recognizedText),
            ));
          }
        }
      } catch (e) {
        print('Error recognizing text in frame $i: $e');
      }
    }

    // Clean up extracted frames
    for (final framePath in frames) {
      try {
        await File(framePath).delete();
      } catch (_) {}
    }

    return textSegments;
  }

  /// Detect captions/subtitles in video
  Future<List<CaptionSegment>> detectCaptions(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 20,
  }) async {
    final captionSegments = <CaptionSegment>[];

    // Extract frames
    final frames = await _visualExtractor.extractFrames(
      videoPath,
      videoDuration,
      startTime: startTime,
      maxFrames: samplePoints,
    );

    for (int i = 0; i < frames.length; i++) {
      final framePath = frames[i];
      final inputImage = InputImage.fromFilePath(framePath);

      try {
        final recognizedText = await _textRecognizer.processImage(inputImage);

        for (final block in recognizedText.blocks) {
          // Check if text is likely a caption (bottom third of screen)
          final boundingBox = block.boundingBox;
          final isLikelyCaption = boundingBox.top > (boundingBox.bottom * 0.66);

          if (isLikelyCaption && block.text.trim().isNotEmpty) {
            final timestamp = Duration(
              milliseconds: (videoDuration.inMilliseconds * i / frames.length).round(),
            );

            captionSegments.add(CaptionSegment(
              timestamp: timestamp,
              text: block.text,
              position: CaptionPosition.bottom,
              confidence: 0.8, // Simplified confidence
            ));
          }
        }
      } catch (e) {
        print('Error detecting captions in frame $i: $e');
      }
    }

    // Clean up extracted frames
    for (final framePath in frames) {
      try {
        await File(framePath).delete();
      } catch (_) {}
    }

    return captionSegments;
  }

  /// Analyze text content for keywords and themes
  Future<List<KeywordSegment>> analyzeKeywords(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    List<String>? targetKeywords,
  }) async {
    final keywordSegments = <KeywordSegment>[];

    // Extract text from video
    final textSegments = await extractTextFromVideo(
      videoPath,
      videoDuration,
      startTime: startTime,
    );

    // Define common interesting keywords if none provided
    final keywords = targetKeywords ?? [
      'new', 'best', 'amazing', 'incredible', 'awesome',
      'tips', 'tutorial', 'how to', 'guide',
      'winner', 'goal', 'score', 'victory',
      'breaking', 'news', 'update', 'announcement',
      'subscribe', 'like', 'follow', 'share',
    ];

    for (final segment in textSegments) {
      final foundKeywords = <String>[];
      final lowercaseText = segment.text.toLowerCase();

      for (final keyword in keywords) {
        if (lowercaseText.contains(keyword.toLowerCase())) {
          foundKeywords.add(keyword);
        }
      }

      if (foundKeywords.isNotEmpty) {
        keywordSegments.add(KeywordSegment(
          timestamp: segment.timestamp,
          keywords: foundKeywords,
          relevanceScore: foundKeywords.length / keywords.length,
        ));
      }
    }

    return keywordSegments;
  }

  /// Calculate importance score based on text content
  double calculateTextImportance(TextSegment segment) {
    // Factors that indicate important text:
    // 1. Length (not too short, not too long)
    // 2. Presence of important words
    // 3. Capitalization patterns
    // 4. Confidence

    final text = segment.text.trim();
    if (text.isEmpty) return 0.0;

    // Length score (prefer 10-50 characters)
    final lengthScore = _calculateLengthScore(text.length);

    // Important words score
    final importantWords = [
      'important', 'key', 'main', 'critical', 'essential',
      'new', 'breaking', 'announcement', 'winner', 'champion',
      'first', 'last', 'final', 'ultimate', 'best',
    ];

    int importantWordCount = 0;
    for (final word in importantWords) {
      if (text.toLowerCase().contains(word)) {
        importantWordCount++;
      }
    }
    final importantWordScore = (importantWordCount / 5).clamp(0.0, 1.0);

    // Capitalization score (some capitals indicate titles/headers)
    final capitalCount = text.codeUnits.where((c) => c >= 65 && c <= 90).length;
    final capitalRatio = capitalCount / text.length;
    final capitalizationScore = capitalRatio > 0.1 && capitalRatio < 0.8 ? 0.8 : 0.4;

    // Combine scores
    return (lengthScore * 0.3 +
            importantWordScore * 0.4 +
            capitalizationScore * 0.2 +
            segment.confidence * 0.1);
  }

  /// Calculate score based on text length
  double _calculateLengthScore(int length) {
    if (length < 5) return 0.2;
    if (length < 10) return 0.5;
    if (length <= 50) return 1.0;
    if (length <= 100) return 0.8;
    return 0.5; // Too long, probably not important
  }

  /// Calculate average confidence from recognized text
  double _calculateAverageConfidence(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) return 0.0;

    // ML Kit doesn't provide confidence directly, so we estimate based on text quality
    double totalScore = 0.0;
    int blockCount = 0;

    for (final block in recognizedText.blocks) {
      // Estimate confidence based on text characteristics
      final text = block.text;
      double blockScore = 0.7; // Base score

      // Adjust based on text quality indicators
      if (text.length > 3) blockScore += 0.1;
      if (RegExp(r'^[a-zA-Z0-9\s.,!?-]+$').hasMatch(text)) blockScore += 0.1;
      if (text.trim().isNotEmpty) blockScore += 0.1;

      totalScore += blockScore.clamp(0.0, 1.0);
      blockCount++;
    }

    return blockCount > 0 ? totalScore / blockCount : 0.0;
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _textRecognizer.close();
    await _visualExtractor.dispose();
  }
}

/// Text segment extracted from video
class TextSegment {
  final Duration timestamp;
  final String text;
  final List<String> textBlocks;
  final double confidence;

  const TextSegment({
    required this.timestamp,
    required this.text,
    required this.textBlocks,
    required this.confidence,
  });
}

/// Caption/subtitle segment
class CaptionSegment {
  final Duration timestamp;
  final String text;
  final CaptionPosition position;
  final double confidence;

  const CaptionSegment({
    required this.timestamp,
    required this.text,
    required this.position,
    required this.confidence,
  });
}

/// Caption position in frame
enum CaptionPosition {
  top,
  middle,
  bottom,
}

/// Keyword detection result
class KeywordSegment {
  final Duration timestamp;
  final List<String> keywords;
  final double relevanceScore;

  const KeywordSegment({
    required this.timestamp,
    required this.keywords,
    required this.relevanceScore,
  });
}
