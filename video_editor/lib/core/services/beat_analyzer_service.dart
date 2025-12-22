import 'dart:math';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';

/// Service for analyzing audio beats
class BeatAnalyzerService {
  final FFmpegVideoEngine _videoEngine;

  BeatAnalyzerService(this._videoEngine);

  /// Analyze beat in audio file
  Future<BeatAnalysisResult> analyzeBeat(String audioFilePath) async {
    // Extract waveform
    final waveform = await _videoEngine.extractWaveform(
      audioFilePath,
      sampleCount: 10000,
    );

    if (waveform.isEmpty) {
      return BeatAnalysisResult(
        beats: [],
        bpm: 0,
        totalDuration: Duration.zero,
      );
    }

    // Get audio info for duration
    final audioInfo = await _videoEngine.getAudioInfo(audioFilePath);
    final duration = audioInfo.duration;

    // Detect onsets (peaks in audio energy)
    final onsets = _detectOnsets(waveform, duration);

    // Identify beats from onsets
    final beats = _identifyBeats(onsets);

    // Calculate BPM
    final bpm = _calculateBPM(beats, duration);

    return BeatAnalysisResult(
      beats: beats,
      bpm: bpm,
      totalDuration: duration,
    );
  }

  /// Calculate BPM from beat markers
  double _calculateBPM(List<BeatMarker> beats, Duration totalDuration) {
    if (beats.length < 2) return 0;

    // Calculate average interval between beats
    var totalInterval = Duration.zero;
    for (var i = 1; i < beats.length; i++) {
      totalInterval += beats[i].timestamp - beats[i - 1].timestamp;
    }

    final avgInterval = totalInterval.inMilliseconds / (beats.length - 1);
    if (avgInterval == 0) return 0;

    // BPM = 60000 / interval_in_ms
    return 60000 / avgInterval;
  }

  /// Detect onset times from waveform
  List<Duration> _detectOnsets(List<double> waveform, Duration duration) {
    final onsets = <Duration>[];
    if (waveform.isEmpty) return onsets;

    // Calculate energy threshold
    final avgEnergy = waveform.reduce((a, b) => a + b) / waveform.length;
    final threshold = avgEnergy * 1.5;

    // Detect peaks above threshold
    final msPerSample = duration.inMilliseconds / waveform.length;

    for (var i = 1; i < waveform.length - 1; i++) {
      if (waveform[i] > threshold &&
          waveform[i] > waveform[i - 1] &&
          waveform[i] > waveform[i + 1]) {
        final timestamp = Duration(milliseconds: (i * msPerSample).round());
        onsets.add(timestamp);
      }
    }

    return onsets;
  }

  /// Identify beat markers from onsets
  List<BeatMarker> _identifyBeats(List<Duration> onsets) {
    final beats = <BeatMarker>[];
    if (onsets.isEmpty) return beats;

    // Calculate median interval
    if (onsets.length < 2) {
      beats.add(BeatMarker(
        timestamp: onsets[0],
        intensity: 1.0,
        type: BeatType.strong,
      ));
      return beats;
    }

    final intervals = <int>[];
    for (var i = 1; i < onsets.length; i++) {
      intervals.add((onsets[i] - onsets[i - 1]).inMilliseconds);
    }
    intervals.sort();
    final medianInterval = intervals[intervals.length ~/ 2];

    // Identify beat types based on intensity and position
    for (var i = 0; i < onsets.length; i++) {
      final intensity = _calculateIntensity(i, onsets, medianInterval);
      final type = _determineBeatType(i, intensity);

      beats.add(BeatMarker(
        timestamp: onsets[i],
        intensity: intensity,
        type: type,
      ));
    }

    return beats;
  }

  double _calculateIntensity(
    int index,
    List<Duration> onsets,
    int medianInterval,
  ) {
    if (index == 0) return 1.0;

    final interval = (onsets[index] - onsets[index - 1]).inMilliseconds;
    final ratio = interval / medianInterval;

    // Beats closer to median interval have higher intensity
    return max(0.3, 1.0 - (ratio - 1.0).abs());
  }

  BeatType _determineBeatType(int index, double intensity) {
    // Every 4th beat is an accent
    if (index % 4 == 0) {
      return BeatType.accent;
    }
    // High intensity beats are strong
    else if (intensity > 0.7) {
      return BeatType.strong;
    }
    // Others are weak
    else {
      return BeatType.weak;
    }
  }
}
