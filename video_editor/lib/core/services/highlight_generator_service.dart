import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/beat_analyzer_service.dart';
import 'package:video_editor/core/services/multimodal_feature_scorer.dart';

/// Service for generating highlight videos
class HighlightGeneratorService {
  final BeatAnalyzerService _beatAnalyzer;
  final MultimodalFeatureScorer _featureScorer;
  final List<MediaItem> _mediaLibrary;

  // Cache for scene detection results
  final Map<String, List<Duration>> _sceneDetectionCache = {};

  // Maximum parallel jobs
  static final int _maxParallelJobs = max(
    2,
    min(Platform.numberOfProcessors, 8),
  );

  HighlightGeneratorService(
    this._beatAnalyzer,
    this._mediaLibrary, {
    MultimodalFeatureScorer? featureScorer,
  }) : _featureScorer = featureScorer ?? MultimodalFeatureScorer();

  static const Duration _minSegmentDuration = Duration(seconds: 1);
  static const Duration _maxSegmentDuration = Duration(seconds: 5);
  static const Duration _fallbackSegmentDuration = Duration(seconds: 3);

  // Beat-based highlights tend to feel too "choppy" if we strictly follow beat
  // intervals (e.g. 120bpm -> 1.5s with 3 beats). Use a wider range.
  static const Duration _beatMinSegmentDuration = Duration(seconds: 2);
  static const Duration _beatMaxSegmentDuration = Duration(seconds: 8);

  static const HighlightPattern _defaultPattern = HighlightPattern.vlog;
  static const HighlightPreferences _defaultPreferences =
      HighlightPreferences();

  String _segmentDedupKey(_SegmentContext context) {
    final startMs = context.segment.start.inMilliseconds;
    final endMs = context.segment.end.inMilliseconds;
    return '${context.clip.id}:$startMs:$endMs';
  }

  List<_SegmentContext> _dedupeSegmentContexts(List<_SegmentContext> segments) {
    final seen = <String>{};
    final out = <_SegmentContext>[];
    for (final s in segments) {
      if (seen.add(_segmentDedupKey(s))) out.add(s);
    }
    return out;
  }

  void _emitProgress(
    HighlightProgressCallback? onProgress,
    HighlightGenerationProgress progress,
  ) {
    if (onProgress == null) return;
    onProgress(progress);
  }

  Future<Timeline> generateHighlight({
    required Timeline baseTimeline,
    required Duration targetDuration,
    HighlightGenerationMode mode = HighlightGenerationMode.time,
    HighlightPattern? pattern,
    HighlightPreferences? preferences,
    MediaItem? bgmTrack,
    HighlightProgressCallback? onProgress,
  }) async {
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(HighlightGenerationStage.preparing),
    );
    final effectivePattern = pattern ?? _defaultPattern;
    final effectivePreferences = preferences ?? _defaultPreferences;

    switch (mode) {
      case HighlightGenerationMode.beat:
        if (bgmTrack == null || bgmTrack.filePath.isEmpty) {
          return generateTimeBasedHighlight(
            baseTimeline,
            targetDuration,
            onProgress: onProgress,
          );
        }
        return generateBeatBasedHighlight(
          baseTimeline,
          bgmTrack,
          targetDuration,
          pattern: effectivePattern,
          preferences: effectivePreferences,
          onProgress: onProgress,
        );
      case HighlightGenerationMode.time:
        return generateTimeBasedHighlight(
          baseTimeline,
          targetDuration,
          pattern: effectivePattern,
          preferences: effectivePreferences,
          onProgress: onProgress,
        );
      case HighlightGenerationMode.pattern:
        return generatePatternHighlight(
          baseTimeline,
          effectivePattern,
          targetDuration,
          effectivePreferences,
          onProgress: onProgress,
        );
    }
  }

  /// Generate beat-based highlight
  Future<Timeline> generateBeatBasedHighlight(
    Timeline baseTimeline,
    MediaItem bgmTrack,
    Duration targetDuration, {
    HighlightPattern pattern = _defaultPattern,
    HighlightPreferences preferences = _defaultPreferences,
    HighlightProgressCallback? onProgress,
  }) async {
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.detectingBeats,
      ),
    );
    // Analyze BGM beats
    final beatAnalysis = await _beatAnalyzer.analyzeBeat(bgmTrack.filePath);

    // Extract strong beats and accents
    final importantBeats = beatAnalysis.beats
        .where((b) => b.type == BeatType.strong || b.type == BeatType.accent)
        .toList();

    final candidates = _dedupeSegmentContexts(
      _extractBeatSegments(
        baseTimeline,
        importantBeats,
        beatAnalysis.bpm,
      ),
    );
    if (candidates.isEmpty) {
      return generateTimeBasedHighlight(
        baseTimeline,
        targetDuration,
        pattern: pattern,
        preferences: preferences,
        onProgress: onProgress,
      );
    }

    final scored = await _scoreSegmentsWithPattern(
      candidates,
      pattern,
      preferences,
      onProgress: onProgress,
    );
    final minGapSeconds = max(pattern.minGapSeconds, preferences.minGapSeconds);
    final diversityWeight = max(
      pattern.diversityWeight,
      preferences.diversityWeight,
    );

    if (preferences.requireAllClips) {
      try {
        final requiredMediaItemIds = _collectRequiredMediaItemIds(baseTimeline);
        final selected = _selectTopSegmentsEnsuringCoverage(
          scored,
          targetDuration,
          requiredMediaItemIds: requiredMediaItemIds,
          oneSegmentPerClip: preferences.oneSegmentPerClip,
        )..sort((a, b) => a.segment.start.compareTo(b.segment.start));
        return _buildHighlightFromSegments(selected, bgmTrack: bgmTrack);
      } on StateError {
        return generateTimeBasedHighlight(
          baseTimeline,
          targetDuration,
          pattern: pattern,
          preferences: preferences,
          onProgress: onProgress,
        );
      }
    }

    // Prefer score-based selection over chronological-first for better quality
    // and fewer repeated segments. Beat alignment is preserved because the
    // candidates themselves are built around beat timestamps.
    final diverse = _applyDiversityConstraints(
      scored,
      minGapSeconds,
      diversityWeight,
      oneSegmentPerClip: preferences.oneSegmentPerClip,
    );
    final selected = _selectTopSegments(diverse, targetDuration)
      ..sort((a, b) => a.segment.start.compareTo(b.segment.start));
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.buildingTimeline,
      ),
    );
    return _buildHighlightFromSegments(selected, bgmTrack: bgmTrack);
  }

  /// Generate time-based highlight
  Future<Timeline> generateTimeBasedHighlight(
    Timeline baseTimeline,
    Duration targetDuration, {
    HighlightPattern pattern = _defaultPattern,
    HighlightPreferences preferences = _defaultPreferences,
    HighlightProgressCallback? onProgress,
  }) async {
    final requiredMediaItemIds = preferences.requireAllClips
        ? _collectRequiredMediaItemIds(baseTimeline)
        : null;
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.detectingScenes,
      ),
    );
    final segments = await _extractAdaptiveSegments(
      baseTimeline,
      onProgress: onProgress,
    );
    final scoredSegments = await _scoreSegmentsWithPattern(
      segments,
      pattern,
      preferences,
      onProgress: onProgress,
    );

    final diverseSegments = _applyDiversityConstraints(
      scoredSegments,
      max(pattern.minGapSeconds, preferences.minGapSeconds),
      max(pattern.diversityWeight, preferences.diversityWeight),
      oneSegmentPerClip: preferences.oneSegmentPerClip,
    );
    final selectionPool = requiredMediaItemIds == null
        ? diverseSegments
        : scoredSegments;
    final selected = (requiredMediaItemIds == null)
        ? _selectTopSegments(selectionPool, targetDuration)
        : _selectTopSegmentsEnsuringCoverage(
            selectionPool,
            targetDuration,
            requiredMediaItemIds: requiredMediaItemIds,
            oneSegmentPerClip: preferences.oneSegmentPerClip,
          );
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.buildingTimeline,
      ),
    );
    selected.sort((a, b) => a.segment.start.compareTo(b.segment.start));
    return _buildHighlightFromSegments(selected);
  }

  /// Generate pattern-based highlight
  Future<Timeline> generatePatternHighlight(
    Timeline baseTimeline,
    HighlightPattern pattern,
    Duration targetDuration,
    HighlightPreferences preferences, {
    HighlightProgressCallback? onProgress,
  }) async {
    final requiredMediaItemIds = preferences.requireAllClips
        ? _collectRequiredMediaItemIds(baseTimeline)
        : null;
    // Extract segments
    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.detectingScenes,
      ),
    );
    final segments = await _extractAdaptiveSegments(
      baseTimeline,
      onProgress: onProgress,
    );

    // Score with pattern weights using real feature extraction
    final scoredSegments = await _scoreSegmentsWithPattern(
      segments,
      pattern,
      preferences,
      onProgress: onProgress,
    );

    // Apply diversity constraints
    final diverseSegments = _applyDiversityConstraints(
      scoredSegments,
      max(pattern.minGapSeconds, preferences.minGapSeconds),
      max(pattern.diversityWeight, preferences.diversityWeight),
      oneSegmentPerClip: preferences.oneSegmentPerClip,
    );
    final selectionPool = requiredMediaItemIds == null
        ? diverseSegments
        : scoredSegments;

    // Select segments to fit duration
    final selectedSegments = (requiredMediaItemIds == null)
        ? _selectTopSegments(selectionPool, targetDuration)
        : _selectTopSegmentsEnsuringCoverage(
            selectionPool,
            targetDuration,
            requiredMediaItemIds: requiredMediaItemIds,
            oneSegmentPerClip: preferences.oneSegmentPerClip,
          );

    // Adjust pace based on pattern
    final adjustedSegments = requiredMediaItemIds == null
        ? _adjustPace(selectedSegments, pattern.paceFactor)
        : selectedSegments;

    _emitProgress(
      onProgress,
      const HighlightGenerationProgress(
        HighlightGenerationStage.buildingTimeline,
      ),
    );
    adjustedSegments.sort((a, b) => a.segment.start.compareTo(b.segment.start));
    return _buildHighlightFromSegments(adjustedSegments);
  }

  Set<String> _collectRequiredMediaItemIds(Timeline timeline) {
    final ids = <String>{};
    for (final track in timeline.videoTracks) {
      for (final clip in track.clips) {
        ids.add(clip.mediaItemId);
      }
    }
    return ids;
  }

  _SegmentContext _trimSegmentContext(
    _SegmentContext context,
    Duration desiredDuration,
  ) {
    final originalDuration = context.segment.duration;
    final clamped = desiredDuration < _minSegmentDuration
        ? _minSegmentDuration
        : desiredDuration > originalDuration
        ? originalDuration
        : desiredDuration;
    if (clamped == originalDuration) return context;
    return _SegmentContext(
      segment: HighlightSegment(
        start: context.segment.start,
        end: context.segment.start + clamped,
        metadata: context.segment.metadata,
      ),
      clip: context.clip,
      track: context.track,
    );
  }

  List<_SegmentContext> _selectTopSegmentsEnsuringCoverage(
    List<_ScoredSegment> scores,
    Duration targetDuration, {
    required Set<String> requiredMediaItemIds,
    required bool oneSegmentPerClip,
  }) {
    if (requiredMediaItemIds.isEmpty) {
      return _selectTopSegments(scores, targetDuration);
    }

    final minRequiredDuration =
        _minSegmentDuration * requiredMediaItemIds.length;
    if (targetDuration < minRequiredDuration) {
      throw StateError(
        'Target duration too short to include all media items: '
        '${requiredMediaItemIds.length} media items require at least '
        '${minRequiredDuration.inSeconds}s.',
      );
    }

    scores.sort((a, b) => b.score.score.compareTo(a.score.score));

    final bestByClipId = <String, _ScoredSegment>{};
    for (final s in scores) {
      bestByClipId.putIfAbsent(s.context.clip.mediaItemId, () => s);
      if (bestByClipId.length == requiredMediaItemIds.length) break;
    }

    final missing = requiredMediaItemIds.where(
      (id) => !bestByClipId.containsKey(id),
    );
    if (missing.isNotEmpty) {
      throw StateError(
        'No candidate segments for some media items: ${missing.join(", ")}',
      );
    }

    var remainingExtra =
        targetDuration - (_minSegmentDuration * requiredMediaItemIds.length);
    final mandatorySortedByScore = List<_ScoredSegment>.from(
      requiredMediaItemIds.map((id) => bestByClipId[id]!),
    )..sort((a, b) => b.score.score.compareTo(a.score.score));

    final selected = <_SegmentContext>[];
    for (final s in mandatorySortedByScore) {
      final original = s.context.segment.duration;
      final availableExtra = original > _minSegmentDuration
          ? original - _minSegmentDuration
          : Duration.zero;
      final allocatedExtra = availableExtra < remainingExtra
          ? availableExtra
          : remainingExtra;
      final desired = _minSegmentDuration + allocatedExtra;
      selected.add(_trimSegmentContext(s.context, desired));
      remainingExtra -= allocatedExtra;
    }

    var totalDuration = selected.fold(
      Duration.zero,
      (acc, s) => acc + s.segment.duration,
    );

    if (oneSegmentPerClip) return selected;

    final selectedSegmentKeys = selected.map(_segmentDedupKey).toSet();
    for (final s in scores) {
      final key = _segmentDedupKey(s.context);
      if (selectedSegmentKeys.contains(key)) continue;
      final segmentDuration = s.context.segment.duration;
      if (totalDuration + segmentDuration <= targetDuration) {
        selected.add(s.context);
        selectedSegmentKeys.add(key);
        totalDuration += segmentDuration;
      } else {
        final remaining = targetDuration - totalDuration;
        if (remaining >= _minSegmentDuration) {
          selected.add(_trimSegmentContext(s.context, remaining));
        }
        break;
      }
    }

    return selected;
  }

  Future<List<_SegmentContext>> _extractAdaptiveSegments(
    Timeline timeline, {
    HighlightProgressCallback? onProgress,
  }) async {
    final segments = <_SegmentContext>[];

    // Collect all clips first
    final allClips = <({Clip clip, Track track})>[];
    for (final track in timeline.videoTracks) {
      for (final clip in track.clips) {
        allClips.add((clip: clip, track: track));
      }
    }

    // Parallel scene detection with batching
    final sceneDetectionResults = await _detectSceneCutsParallel(
      allClips.map((e) => e.clip).toList(),
      onProgress: onProgress,
    );

    // Build segments from detection results
    for (var i = 0; i < allClips.length; i++) {
      final clip = allClips[i].clip;
      final track = allClips[i].track;
      final sceneCuts = sceneDetectionResults[i];

      final boundaries = _buildSegmentBoundaries(clip.duration, sceneCuts);

      for (var j = 0; j < boundaries.length - 1; j++) {
        final start = boundaries[j];
        final end = boundaries[j + 1];
        if (end <= start) continue;

        var segStart = start;
        while (segStart < end) {
          final segEnd = _minDuration(end, segStart + _maxSegmentDuration);
          final segDur = segEnd - segStart;
          if (segDur < _minSegmentDuration) break;

          final timelineStart = clip.startTime + segStart;
          final timelineEnd = clip.startTime + segEnd;
          if (timelineEnd <= timelineStart) break;

          final segment = HighlightSegment(
            start: timelineStart,
            end: timelineEnd,
            metadata: {
              'clipId': clip.id,
              'trackId': track.id,
              'mediaItemId': clip.mediaItemId,
            },
          );
          segments.add(
            _SegmentContext(segment: segment, clip: clip, track: track),
          );

          segStart = segEnd;
        }
      }
    }

    return segments;
  }

  /// Detect scene cuts for multiple clips in parallel
  Future<List<List<Duration>>> _detectSceneCutsParallel(
    List<Clip> clips, {
    HighlightProgressCallback? onProgress,
  }) async {
    final results = <List<Duration>>[];
    final total = clips.length;
    var completed = 0;

    // Process clips in batches to limit parallelism
    for (var i = 0; i < clips.length; i += _maxParallelJobs) {
      final batch = clips.skip(i).take(_maxParallelJobs).toList();
      final batchResults = await Future.wait(
        batch.map((clip) async {
          final out = await _detectSceneCutsForClip(clip);
          completed++;
          _emitProgress(
            onProgress,
            HighlightGenerationProgress(
              HighlightGenerationStage.detectingScenes,
              completed: completed,
              total: total,
            ),
          );
          return out;
        }),
      );
      results.addAll(batchResults);
    }

    return results;
  }

  Future<List<Duration>> _detectSceneCutsForClip(Clip clip) async {
    // Check cache first
    final cacheKey =
        '${clip.mediaItemId}_${clip.sourceStart.inMilliseconds}_${clip.sourceDuration.inMilliseconds}';
    if (_sceneDetectionCache.containsKey(cacheKey)) {
      return _sceneDetectionCache[cacheKey]!;
    }

    // If we can't locate media, fall back to fixed segmentation.
    final mediaItem = _mediaLibrary.cast<MediaItem?>().firstWhere(
      (item) => item?.id == clip.mediaItemId,
      orElse: () => null,
    );
    final path = mediaItem?.filePath;
    if (path == null || path.isEmpty) return const [];
    if (!File(path).existsSync()) return const [];
    if (clip.sourceDuration <= Duration.zero) return const [];

    // Optimized FFmpeg parameters for faster scene detection
    final args = <String>[
      '-hide_banner',
      '-loglevel',
      'info',
      // Use hardware acceleration if available (macOS)
      if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
      if (clip.sourceStart > Duration.zero) ...[
        '-ss',
        (clip.sourceStart.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      '-t',
      (clip.sourceDuration.inMilliseconds / 1000.0).toStringAsFixed(2),
      '-i',
      path,
      // Optimized filter: lower resolution + higher threshold for faster processing
      '-vf',
      'scale=640:-1,fps=5,select=gt(scene\\,0.35),showinfo',
      // Use multiple threads
      '-threads',
      '0',
      '-f',
      'null',
      '-',
    ];

    try {
      var result = await Process.run('ffmpeg', args, runInShell: false);
      if (result.exitCode != 0 && Platform.isMacOS) {
        final fallbackArgs = args
            .where((a) => a != 'videotoolbox' && a != '-hwaccel')
            .toList();
        result = await Process.run('ffmpeg', fallbackArgs, runInShell: false);
      }

      final stderr = result.stderr.toString();
      if (stderr.isEmpty) {
        _sceneDetectionCache[cacheKey] = const [];
        return const [];
      }

      final cuts = <Duration>[];
      for (final line in stderr.split('\n')) {
        if (!line.contains('Parsed_showinfo') || !line.contains('pts_time:')) {
          continue;
        }
        final match = RegExp(r'pts_time:([\d.]+)').firstMatch(line);
        if (match == null) continue;
        final seconds = double.tryParse(match.group(1) ?? '');
        if (seconds == null) continue;
        final ts = Duration(milliseconds: (seconds * 1000).round());
        if (ts > Duration.zero && ts < clip.sourceDuration) {
          cuts.add(ts);
        }
      }
      cuts.sort();

      // Cache the result
      _sceneDetectionCache[cacheKey] = cuts;
      return cuts;
    } catch (e) {
      // On error, return empty and cache it
      _sceneDetectionCache[cacheKey] = const [];
      return const [];
    }
  }

  List<Duration> _buildSegmentBoundaries(
    Duration total,
    List<Duration> sceneCuts,
  ) {
    // If scene detection yields nothing, fall back to fixed-length boundaries.
    if (sceneCuts.isEmpty) {
      final boundaries = <Duration>[Duration.zero];
      var t = Duration.zero;
      while (t < total) {
        t += _fallbackSegmentDuration;
        boundaries.add(t > total ? total : t);
      }
      return boundaries;
    }

    final boundaries = <Duration>[Duration.zero, ...sceneCuts, total]
      ..sort((a, b) => a.compareTo(b));

    // Merge tiny segments to avoid noisy cuts.
    final merged = <Duration>[boundaries.first];
    for (var i = 1; i < boundaries.length; i++) {
      final last = merged.last;
      final current = boundaries[i];
      if (current - last < _minSegmentDuration && i < boundaries.length - 1) {
        continue;
      }
      merged.add(current);
    }
    if (merged.last != total) merged.add(total);
    return merged;
  }

  Future<List<_ScoredSegment>> _scoreSegmentsWithPattern(
    List<_SegmentContext> segments,
    HighlightPattern pattern,
    HighlightPreferences preferences, {
    HighlightProgressCallback? onProgress,
  }) async {
    final dedupedSegments = _dedupeSegmentContexts(segments);
    final scored = <_ScoredSegment>[];
    final preferenceMultiplier = _calculatePreferenceMultiplier(preferences);
    final total = dedupedSegments.length;
    _emitProgress(
      onProgress,
      HighlightGenerationProgress(
        HighlightGenerationStage.scoringSegments,
        completed: 0,
        total: total,
      ),
    );

    // Process segments in parallel batches
    for (var i = 0; i < dedupedSegments.length; i += _maxParallelJobs) {
      final batch = dedupedSegments.skip(i).take(_maxParallelJobs).toList();

      final batchResults = await Future.wait(
        batch.map(
          (context) => _scoreSegment(context, pattern, preferenceMultiplier),
        ),
      );

      scored.addAll(batchResults);
      _emitProgress(
        onProgress,
        HighlightGenerationProgress(
          HighlightGenerationStage.scoringSegments,
          completed: min(i + batch.length, total),
          total: total,
        ),
      );
    }

    return scored;
  }

  Future<_ScoredSegment> _scoreSegment(
    _SegmentContext context,
    HighlightPattern pattern,
    double preferenceMultiplier,
  ) async {
    try {
      // Get media file path
      final mediaItem = _mediaLibrary.firstWhere(
        (item) => item.id == context.clip.mediaItemId,
        orElse: () => throw Exception(
          'Media item not found: ${context.clip.mediaItemId}',
        ),
      );

      // Calculate the actual video timestamps for this segment
      final sourceOffset = context.segment.start - context.clip.startTime;
      final videoStart = context.clip.sourceStart + sourceOffset;
      final videoEnd = videoStart + context.segment.duration;

      // Extract features and score segment
      final score = await _featureScorer.scoreSegment(
        mediaItem.filePath,
        videoStart,
        videoEnd,
        pattern,
      );

      // Apply user preferences as multipliers
      final adjustedScore = (score * preferenceMultiplier).clamp(0.0, 1.0);

      return _ScoredSegment(
        context: context,
        score: HighlightScore(
          segmentId: context.segment.id,
          score: adjustedScore,
          breakdown: {
            'visual': adjustedScore * pattern.weights['visual']!,
            'audio': adjustedScore * pattern.weights['audio']!,
            'text': adjustedScore * pattern.weights['text']!,
          },
        ),
      );
    } catch (e) {
      // Use fallback scoring on error or missing media.
      final seconds = context.segment.duration.inMilliseconds / 1000.0;
      final fallback = seconds >= 2.0 ? 0.7 : 0.5;
      return _ScoredSegment(
        context: context,
        score: HighlightScore(
          segmentId: context.segment.id,
          score: fallback,
          breakdown: {
            'visual': fallback * 0.4,
            'audio': fallback * 0.4,
            'text': fallback * 0.2,
          },
        ),
      );
    }
  }

  double _calculatePreferenceMultiplier(HighlightPreferences preferences) {
    // Start with base multiplier
    double multiplier = 1.0;

    // Adjust based on preferences
    if (preferences.preferHighMotion) multiplier *= 1.1;
    if (preferences.preferFaces) multiplier *= 1.1;
    if (preferences.preferSpeechPeaks) multiplier *= 1.1;

    return multiplier;
  }

  List<_SegmentContext> _extractBeatSegments(
    Timeline timeline,
    List<BeatMarker> beats,
    double bpm,
  ) {
    if (beats.isEmpty) return const [];

    var intervalMs = 500.0;
    if (bpm > 0) {
      intervalMs = 60000.0 / bpm;
    } else if (beats.length >= 2) {
      final diffs = <int>[];
      for (var i = 1; i < beats.length; i++) {
        diffs.add((beats[i].timestamp - beats[i - 1].timestamp).inMilliseconds);
      }
      diffs.sort();
      intervalMs = diffs[diffs.length ~/ 2].toDouble().clamp(200.0, 1500.0);
    }

    final desiredMs = (intervalMs * 8).clamp(
      _beatMinSegmentDuration.inMilliseconds.toDouble(),
      _beatMaxSegmentDuration.inMilliseconds.toDouble(),
    );
    final desired = Duration(milliseconds: desiredMs.round());
    final pre = Duration(milliseconds: (desired.inMilliseconds * 0.25).round());
    final post = desired - pre;

    final contexts = <_SegmentContext>[];
    final seen = <String>{};
    for (final beat in beats) {
      for (final track in timeline.videoTracks) {
        for (final clip in track.clips) {
          if (clip.startTime <= beat.timestamp &&
              beat.timestamp < clip.endTime) {
            var start = beat.timestamp - pre;
            var end = beat.timestamp + post;
            if (start < clip.startTime) {
              start = clip.startTime;
              end = start + desired;
            }
            if (end > clip.endTime) {
              end = clip.endTime;
              start = end - desired;
              if (start < clip.startTime) start = clip.startTime;
            }
            if (end - start < _beatMinSegmentDuration) break;

            final segment = HighlightSegment(
              start: start,
              end: end,
              metadata: {
                'clipId': clip.id,
                'trackId': track.id,
                'mediaItemId': clip.mediaItemId,
                'beatMs': beat.timestamp.inMilliseconds,
                'beatType': beat.type.name,
              },
            );
            final context =
                _SegmentContext(segment: segment, clip: clip, track: track);
            if (seen.add(_segmentDedupKey(context))) {
              contexts.add(context);
            }
            break;
          }
        }
      }
    }
    return contexts;
  }

  List<_ScoredSegment> _applyDiversityConstraints(
    List<_ScoredSegment> scores,
    int minGapSeconds,
    double diversityWeight, {
    bool oneSegmentPerClip = false,
  }) {
    // Sort by score
    scores.sort((a, b) => b.score.score.compareTo(a.score.score));

    // Apply temporal and content diversity
    final selected = <_ScoredSegment>[];
    final minGapDuration = Duration(seconds: minGapSeconds);

    for (final score in scores) {
      var shouldInclude = true;

      // Check temporal diversity: ensure minimum gap between segments
      for (final selectedScore in selected) {
        final segmentStart = score.context.segment.start;
        final segmentEnd = score.context.segment.end;
        final selectedStart = selectedScore.context.segment.start;
        final selectedEnd = selectedScore.context.segment.end;

        // Check if segments overlap or are too close
        final gap = _calculateGap(
          segmentStart,
          segmentEnd,
          selectedStart,
          selectedEnd,
        );

        if (gap < minGapDuration) {
          shouldInclude = false;
          break;
        }
      }

      // Check content diversity: avoid too many segments from same clip
      if (shouldInclude) {
        final sameClipCount = selected.where(
          (s) => s.context.clip.mediaItemId == score.context.clip.mediaItemId,
        ).length;

        // Limit segments from same clip based on diversity weight
        final maxSameClip = oneSegmentPerClip
            ? 1
            : (10 * (1 - diversityWeight)).round() + 2;
        if (sameClipCount >= maxSameClip) {
          shouldInclude = false;
        }
      }

      if (shouldInclude) {
        selected.add(score);

        // Cap total segments to prevent overly long highlights
        if (selected.length >= 50) {
          break;
        }
      }
    }

    return selected;
  }

  /// Calculate gap between two time ranges
  Duration _calculateGap(
    Duration start1,
    Duration end1,
    Duration start2,
    Duration end2,
  ) {
    // If segments overlap, gap is zero
    if (start1 < end2 && start2 < end1) {
      return Duration.zero;
    }

    // Calculate gap between segments
    if (end1 <= start2) {
      return start2 - end1;
    } else {
      return start1 - end2;
    }
  }

  List<_SegmentContext> _selectTopSegments(
    List<_ScoredSegment> scores,
    Duration targetDuration,
  ) {
    scores.sort((a, b) => b.score.score.compareTo(a.score.score));

    final selected = <_SegmentContext>[];
    var totalDuration = Duration.zero;

    for (final score in scores) {
      final segmentDuration = score.context.segment.duration;

      if (totalDuration + segmentDuration <= targetDuration) {
        selected.add(score.context);
        totalDuration += segmentDuration;
      } else {
        break;
      }
    }

    return selected;
  }

  List<_SegmentContext> _selectBeatSegments(
    List<_ScoredSegment> scores,
    Duration targetDuration, {
    required int minGapSeconds,
    required double diversityWeight,
    bool oneSegmentPerClip = false,
  }) {
    final sortedByTime = List<_ScoredSegment>.from(scores)
      ..sort(
        (a, b) => a.context.segment.start.compareTo(b.context.segment.start),
      );

    final selected = <_ScoredSegment>[];
    var totalDuration = Duration.zero;
    final minGapDuration = Duration(seconds: minGapSeconds);

    for (final score in sortedByTime) {
      final segmentDuration = score.context.segment.duration;
      if (totalDuration + segmentDuration > targetDuration) break;

      var ok = true;
      for (final chosen in selected) {
        final gap = _calculateGap(
          score.context.segment.start,
          score.context.segment.end,
          chosen.context.segment.start,
          chosen.context.segment.end,
        );
        if (gap < minGapDuration) {
          ok = false;
          break;
        }
      }

      if (ok) {
        final sameClipCount = selected.where(
          (s) => s.context.clip.mediaItemId == score.context.clip.mediaItemId,
        ).length;
        final maxSameClip = oneSegmentPerClip
            ? 1
            : (10 * (1 - diversityWeight)).round() + 2;
        if (sameClipCount >= maxSameClip) ok = false;
      }

      if (!ok) continue;
      selected.add(score);
      totalDuration += segmentDuration;
    }

    return selected.map((s) => s.context).toList();
  }

  List<_SegmentContext> _adjustPace(
    List<_SegmentContext> segments,
    double paceFactor,
  ) {
    // Adjust segment count based on pace factor
    final targetCount = (segments.length * paceFactor).round();
    return segments.take(targetCount).toList();
  }

  Timeline _buildHighlightFromSegments(
    List<_SegmentContext> segments, {
    MediaItem? bgmTrack,
  }) {
    var timeline = Timeline();

    final videoTrack = Track(type: TrackType.video, name: 'Highlight Video');
    timeline = timeline.addTrack(videoTrack);

    var currentTime = Duration.zero;
    final used = <String>{};
    for (final context in segments) {
      if (!used.add(_segmentDedupKey(context))) {
        continue;
      }
      final sourceOffset = context.segment.start - context.clip.startTime;
      final sourceStart = context.clip.sourceStart + sourceOffset;
      final duration = context.segment.duration;

      // Add video clip (audio is included in the video and controlled via Properties panel)
      final videoClip = Clip(
        mediaItemId: context.clip.mediaItemId,
        startTime: currentTime,
        endTime: currentTime + duration,
        sourceStart: sourceStart,
        sourceDuration: duration,
      );
      timeline = timeline.addClipToTrack(videoTrack.id, videoClip);

      currentTime += duration;
    }

    // Add BGM track only if BGM is specified
    if (bgmTrack != null &&
        bgmTrack.filePath.isNotEmpty &&
        currentTime > Duration.zero) {
      final bgmAudioTrack = Track(type: TrackType.audio, name: 'BGM');
      timeline = timeline.addTrack(bgmAudioTrack);
      final bgmClip = Clip(
        mediaItemId: bgmTrack.id,
        startTime: Duration.zero,
        endTime: currentTime,
        sourceStart: Duration.zero,
        sourceDuration: currentTime,
      );
      timeline = timeline.addClipToTrack(bgmAudioTrack.id, bgmClip);
    }

    return timeline;
  }

  Duration _minDuration(Duration a, Duration b) => a < b ? a : b;
}

class _SegmentContext {
  final HighlightSegment segment;
  final Clip clip;
  final Track track;

  const _SegmentContext({
    required this.segment,
    required this.clip,
    required this.track,
  });
}

class _ScoredSegment {
  final _SegmentContext context;
  final HighlightScore score;

  const _ScoredSegment({required this.context, required this.score});
}

extension HighlightGeneratorServiceDispose on HighlightGeneratorService {
  /// Clean up resources
  Future<void> dispose() async {
    await _featureScorer.dispose();
    _sceneDetectionCache.clear();
  }

  /// Clear scene detection cache
  void clearCache() {
    _sceneDetectionCache.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedClips': _sceneDetectionCache.length,
      'cacheKeys': _sceneDetectionCache.keys.toList(),
    };
  }
}

enum HighlightGenerationMode { beat, time, pattern }

typedef HighlightProgressCallback =
    void Function(HighlightGenerationProgress progress);

enum HighlightGenerationStage {
  preparing,
  detectingBeats,
  detectingScenes,
  scoringSegments,
  buildingTimeline,
  done,
}

class HighlightGenerationProgress {
  final HighlightGenerationStage stage;
  final int? completed;
  final int? total;
  final String? message;

  const HighlightGenerationProgress(
    this.stage, {
    this.completed,
    this.total,
    this.message,
  });

  double? get fraction {
    final c = completed;
    final t = total;
    if (c == null || t == null || t <= 0) return null;
    return (c / t).clamp(0.0, 1.0);
  }

  String get stageLabel {
    switch (stage) {
      case HighlightGenerationStage.preparing:
        return '準備中';
      case HighlightGenerationStage.detectingBeats:
        return 'BGM解析中';
      case HighlightGenerationStage.detectingScenes:
        return 'シーン解析中';
      case HighlightGenerationStage.scoringSegments:
        return 'スコア計算中';
      case HighlightGenerationStage.buildingTimeline:
        return 'タイムライン作成中';
      case HighlightGenerationStage.done:
        return '完了';
    }
  }
}
