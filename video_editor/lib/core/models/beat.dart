import 'package:json_annotation/json_annotation.dart';
import 'enums.dart';

part 'beat.g.dart';

/// A beat marker in the audio
@JsonSerializable()
class BeatMarker {
  final Duration timestamp;
  final double intensity;
  final BeatType type;

  const BeatMarker({
    required this.timestamp,
    required this.intensity,
    required this.type,
  });

  factory BeatMarker.fromJson(Map<String, dynamic> json) =>
      _$BeatMarkerFromJson(json);

  Map<String, dynamic> toJson() => _$BeatMarkerToJson(this);
}

/// Result of beat analysis
@JsonSerializable()
class BeatAnalysisResult {
  final List<BeatMarker> beats;
  final double bpm;
  final Duration totalDuration;

  const BeatAnalysisResult({
    required this.beats,
    required this.bpm,
    required this.totalDuration,
  });

  factory BeatAnalysisResult.fromJson(Map<String, dynamic> json) =>
      _$BeatAnalysisResultFromJson(json);

  Map<String, dynamic> toJson() => _$BeatAnalysisResultToJson(this);

  /// Get beats within a specific time range
  List<BeatMarker> getBeatsInRange(Duration start, Duration end) {
    return beats
        .where((b) =>
            b.timestamp.inMicroseconds >= start.inMicroseconds &&
            b.timestamp.inMicroseconds <= end.inMicroseconds)
        .toList();
  }

  /// Get strong beats only
  List<BeatMarker> get strongBeats =>
      beats.where((b) => b.type == BeatType.strong).toList();

  /// Get accent beats only
  List<BeatMarker> get accentBeats =>
      beats.where((b) => b.type == BeatType.accent).toList();
}
