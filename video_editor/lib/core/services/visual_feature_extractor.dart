import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Service for extracting visual features from videos
class VisualFeatureExtractor {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
    ),
  );

  /// Extract frames from video at specified interval
  /// Returns paths to extracted frame files
  Future<List<String>> extractFrames(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int maxFrames = 30,
    String? outputDir,
  }) async {
    final tempDir = outputDir ?? Directory.systemTemp.path;
    final frameDir = Directory('$tempDir/frames_${DateTime.now().millisecondsSinceEpoch}');
    await frameDir.create(recursive: true);

    // Calculate interval to get evenly spaced frames
    final intervalSeconds = videoDuration.inSeconds / maxFrames;

    final framePaths = <String>[];

    // Use FFmpeg to extract frames
    for (int i = 0; i < maxFrames; i++) {
      final timestamp = i * intervalSeconds;
      final absoluteSeconds =
          startTime.inMilliseconds / 1000.0 + timestamp.toDouble();
      final outputPath = '${frameDir.path}/frame_${i.toString().padLeft(4, '0')}.jpg';

      final result = await Process.run('ffmpeg', [
        '-ss', absoluteSeconds.toStringAsFixed(2),
        '-i', videoPath,
        '-vframes', '1',
        '-q:v', '2',
        outputPath,
      ]);

      if (result.exitCode == 0 && File(outputPath).existsSync()) {
        framePaths.add(outputPath);
      }
    }

    return framePaths;
  }

  /// Detect scene changes in video
  /// Returns timestamps of scene changes with confidence scores
  Future<List<SceneChange>> detectSceneChanges(
    String videoPath,
    Duration videoDuration,
    {Duration startTime = Duration.zero}
  ) async {
    final sceneChanges = <SceneChange>[];

    // Use FFmpeg's scene detection
    final result = await Process.run('ffmpeg', [
      if (startTime > Duration.zero) ...[
        '-ss',
        (startTime.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      if (videoDuration > Duration.zero) ...[
        '-t',
        (videoDuration.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      '-i', videoPath,
      '-vf', 'select=gt(scene\\,0.3),showinfo',
      '-f', 'null',
      '-',
    ], runInShell: true);

    // Parse FFmpeg output for scene changes
    final lines = result.stderr.toString().split('\n');
    for (final line in lines) {
      if (line.contains('Parsed_showinfo') && line.contains('pts_time:')) {
        final match = RegExp(r'pts_time:([\d.]+)').firstMatch(line);
        if (match != null) {
          final timestamp = double.parse(match.group(1)!);
          sceneChanges.add(SceneChange(
            timestamp: Duration(milliseconds: (timestamp * 1000).round()),
            confidence: 0.8, // Default confidence from FFmpeg threshold
          ));
        }
      }
    }

    return sceneChanges;
  }

  /// Calculate motion intensity from consecutive frames
  Future<List<MotionSegment>> analyzeMotion(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 20,
  }) async {
    final motionSegments = <MotionSegment>[];

    // Extract frames for motion analysis
    final frames = await extractFrames(
      videoPath,
      videoDuration,
      startTime: startTime,
      maxFrames: samplePoints,
    );

    if (frames.length < 2) {
      return motionSegments;
    }

    // Analyze motion between consecutive frames
    for (int i = 0; i < frames.length - 1; i++) {
      final frame1 = await _loadImage(frames[i]);
      final frame2 = await _loadImage(frames[i + 1]);

      if (frame1 != null && frame2 != null) {
        final motionScore = _calculateFrameDifference(frame1, frame2);
        final timestamp = Duration(
          milliseconds: (videoDuration.inMilliseconds * i / frames.length).round(),
        );

        motionSegments.add(MotionSegment(
          startTime: timestamp,
          endTime: timestamp + Duration(
            milliseconds: (videoDuration.inMilliseconds / frames.length).round(),
          ),
          motionIntensity: motionScore,
        ));
      }
    }

    // Clean up extracted frames
    for (final framePath in frames) {
      try {
        await File(framePath).delete();
      } catch (_) {}
    }

    return motionSegments;
  }

  /// Detect faces in video frames
  Future<List<FaceSegment>> detectFaces(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 15,
  }) async {
    final faceSegments = <FaceSegment>[];

    // Extract frames for face detection
    final frames = await extractFrames(
      videoPath,
      videoDuration,
      startTime: startTime,
      maxFrames: samplePoints,
    );

    for (int i = 0; i < frames.length; i++) {
      final framePath = frames[i];
      final inputImage = InputImage.fromFilePath(framePath);

      try {
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          final timestamp = Duration(
            milliseconds: (videoDuration.inMilliseconds * i / frames.length).round(),
          );

          faceSegments.add(FaceSegment(
            timestamp: timestamp,
            faceCount: faces.length,
            confidence: faces.map((f) => f.smilingProbability ?? 0.5).reduce((a, b) => a + b) / faces.length,
            hasSmile: faces.any((f) => (f.smilingProbability ?? 0) > 0.7),
          ));
        }
      } catch (e) {
        print('Error detecting faces in frame $i: $e');
      }
    }

    // Clean up extracted frames
    for (final framePath in frames) {
      try {
        await File(framePath).delete();
      } catch (_) {}
    }

    return faceSegments;
  }

  /// Analyze visual aesthetics (brightness, contrast, color)
  Future<List<AestheticSegment>> analyzeAesthetics(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 20,
  }) async {
    final aestheticSegments = <AestheticSegment>[];

    final frames = await extractFrames(
      videoPath,
      videoDuration,
      startTime: startTime,
      maxFrames: samplePoints,
    );

    for (int i = 0; i < frames.length; i++) {
      final image = await _loadImage(frames[i]);

      if (image != null) {
        final timestamp = Duration(
          milliseconds: (videoDuration.inMilliseconds * i / frames.length).round(),
        );

        aestheticSegments.add(AestheticSegment(
          timestamp: timestamp,
          brightness: _calculateBrightness(image),
          contrast: _calculateContrast(image),
          colorfulness: _calculateColorfulness(image),
        ));
      }
    }

    // Clean up extracted frames
    for (final framePath in frames) {
      try {
        await File(framePath).delete();
      } catch (_) {}
    }

    return aestheticSegments;
  }

  /// Load image from file
  Future<img.Image?> _loadImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return img.decodeImage(bytes);
    } catch (e) {
      print('Error loading image $path: $e');
      return null;
    }
  }

  /// Calculate difference between two frames (motion intensity)
  double _calculateFrameDifference(img.Image frame1, img.Image frame2) {
    // Resize for faster processing
    final small1 = img.copyResize(frame1, width: 64, height: 64);
    final small2 = img.copyResize(frame2, width: 64, height: 64);

    double totalDiff = 0;
    int pixelCount = 0;

    for (int y = 0; y < small1.height; y++) {
      for (int x = 0; x < small1.width; x++) {
        final pixel1 = small1.getPixel(x, y);
        final pixel2 = small2.getPixel(x, y);

        final r1 = pixel1.r.toInt();
        final g1 = pixel1.g.toInt();
        final b1 = pixel1.b.toInt();
        final r2 = pixel2.r.toInt();
        final g2 = pixel2.g.toInt();
        final b2 = pixel2.b.toInt();

        final diff = sqrt(
          pow(r2 - r1, 2) + pow(g2 - g1, 2) + pow(b2 - b1, 2),
        );

        totalDiff += diff;
        pixelCount++;
      }
    }

    // Normalize to 0-1 range
    return (totalDiff / pixelCount) / 442.0; // Max possible difference for RGB
  }

  /// Calculate average brightness of image
  double _calculateBrightness(img.Image image) {
    final small = img.copyResize(image, width: 64, height: 64);
    double totalBrightness = 0;
    int pixelCount = 0;

    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final pixel = small.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Calculate perceived brightness
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    return totalBrightness / pixelCount;
  }

  /// Calculate contrast of image
  double _calculateContrast(img.Image image) {
    final small = img.copyResize(image, width: 64, height: 64);
    final brightnesses = <double>[];

    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final pixel = small.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        brightnesses.add(brightness);
      }
    }

    // Calculate standard deviation as contrast measure
    final mean = brightnesses.reduce((a, b) => a + b) / brightnesses.length;
    final variance = brightnesses
        .map((b) => pow(b - mean, 2))
        .reduce((a, b) => a + b) / brightnesses.length;

    return sqrt(variance);
  }

  /// Calculate colorfulness of image
  double _calculateColorfulness(img.Image image) {
    final small = img.copyResize(image, width: 64, height: 64);
    double totalSaturation = 0;
    int pixelCount = 0;

    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final pixel = small.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;

        final maxC = max(max(r, g), b);
        final minC = min(min(r, g), b);
        final saturation = (maxC - minC) / (maxC + 0.0001);

        totalSaturation += saturation;
        pixelCount++;
      }
    }

    return totalSaturation / pixelCount;
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _faceDetector.close();
  }
}

/// Scene change detection result
class SceneChange {
  final Duration timestamp;
  final double confidence;

  const SceneChange({
    required this.timestamp,
    required this.confidence,
  });
}

/// Motion analysis result
class MotionSegment {
  final Duration startTime;
  final Duration endTime;
  final double motionIntensity; // 0-1, higher = more motion

  const MotionSegment({
    required this.startTime,
    required this.endTime,
    required this.motionIntensity,
  });
}

/// Face detection result
class FaceSegment {
  final Duration timestamp;
  final int faceCount;
  final double confidence;
  final bool hasSmile;

  const FaceSegment({
    required this.timestamp,
    required this.faceCount,
    required this.confidence,
    required this.hasSmile,
  });
}

/// Aesthetic analysis result
class AestheticSegment {
  final Duration timestamp;
  final double brightness; // 0-1
  final double contrast; // 0-1
  final double colorfulness; // 0-1

  const AestheticSegment({
    required this.timestamp,
    required this.brightness,
    required this.contrast,
    required this.colorfulness,
  });

  double get aestheticScore {
    // Prefer well-lit, high-contrast, colorful frames
    final brightnessScore = 1.0 - (brightness - 0.5).abs() * 2; // Prefer middle brightness
    final contrastScore = contrast; // Higher contrast is better
    final colorScore = colorfulness; // More colorful is better

    return (brightnessScore * 0.3 + contrastScore * 0.4 + colorScore * 0.3);
  }
}
