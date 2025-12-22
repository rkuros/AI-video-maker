import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'highlight.g.dart';

const _uuid = Uuid();

/// Predefined patterns for highlight generation
@JsonSerializable()
class HighlightPattern {
  final String id;
  final String name;
  final Map<String, double> weights; // visual/audio/text
  final int minGapSeconds;
  final double diversityWeight;
  final double paceFactor; // cuts per minute tuning

  const HighlightPattern({
    required this.id,
    required this.name,
    required this.weights,
    this.minGapSeconds = 5,
    this.diversityWeight = 0.3,
    this.paceFactor = 1.0,
  });

  factory HighlightPattern.fromJson(Map<String, dynamic> json) =>
      _$HighlightPatternFromJson(json);

  Map<String, dynamic> toJson() => _$HighlightPatternToJson(this);

  // Predefined patterns
  static const sports = HighlightPattern(
    id: 'sports',
    name: 'Sports',
    weights: {'visual': 0.5, 'audio': 0.4, 'text': 0.1},
    minGapSeconds: 3,
    diversityWeight: 0.4,
    paceFactor: 1.5,
  );

  static const travel = HighlightPattern(
    id: 'travel',
    name: 'Travel',
    weights: {'visual': 0.6, 'audio': 0.2, 'text': 0.2},
    minGapSeconds: 8,
    diversityWeight: 0.5,
    paceFactor: 0.7,
  );

  static const vlog = HighlightPattern(
    id: 'vlog',
    name: 'Vlog',
    weights: {'visual': 0.3, 'audio': 0.3, 'text': 0.4},
    minGapSeconds: 5,
    diversityWeight: 0.3,
    paceFactor: 1.0,
  );

  static const gaming = HighlightPattern(
    id: 'gaming',
    name: 'Gaming',
    weights: {'visual': 0.4, 'audio': 0.5, 'text': 0.1},
    minGapSeconds: 2,
    diversityWeight: 0.3,
    paceFactor: 1.8,
  );

  static const interview = HighlightPattern(
    id: 'interview',
    name: 'Interview',
    weights: {'visual': 0.2, 'audio': 0.4, 'text': 0.4},
    minGapSeconds: 10,
    diversityWeight: 0.2,
    paceFactor: 0.5,
  );

  static const tutorial = HighlightPattern(
    id: 'tutorial',
    name: 'Tutorial',
    weights: {'visual': 0.3, 'audio': 0.2, 'text': 0.5},
    minGapSeconds: 15,
    diversityWeight: 0.4,
    paceFactor: 0.6,
  );

  static const allPatterns = [
    sports,
    travel,
    vlog,
    gaming,
    interview,
    tutorial,
  ];
}

/// User preferences for highlight generation
@JsonSerializable()
class HighlightPreferences {
  final Map<String, double> modalityWeights; // visual/audio/text
  final double diversityWeight;
  final int minGapSeconds;
  final bool preferHighMotion;
  final bool preferFaces;
  final bool preferSpeechPeaks;

  const HighlightPreferences({
    this.modalityWeights = const {'visual': 0.4, 'audio': 0.4, 'text': 0.2},
    this.diversityWeight = 0.3,
    this.minGapSeconds = 5,
    this.preferHighMotion = true,
    this.preferFaces = true,
    this.preferSpeechPeaks = true,
  });

  factory HighlightPreferences.fromJson(Map<String, dynamic> json) =>
      _$HighlightPreferencesFromJson(json);

  Map<String, dynamic> toJson() => _$HighlightPreferencesToJson(this);

  HighlightPreferences copyWith({
    Map<String, double>? modalityWeights,
    double? diversityWeight,
    int? minGapSeconds,
    bool? preferHighMotion,
    bool? preferFaces,
    bool? preferSpeechPeaks,
  }) {
    return HighlightPreferences(
      modalityWeights: modalityWeights ?? Map.from(this.modalityWeights),
      diversityWeight: diversityWeight ?? this.diversityWeight,
      minGapSeconds: minGapSeconds ?? this.minGapSeconds,
      preferHighMotion: preferHighMotion ?? this.preferHighMotion,
      preferFaces: preferFaces ?? this.preferFaces,
      preferSpeechPeaks: preferSpeechPeaks ?? this.preferSpeechPeaks,
    );
  }
}

/// User preference profile learned from past interactions
@JsonSerializable()
class UserPreferenceProfile {
  final String userId;
  final Map<String, double> learnedWeights;
  final List<String> rejectedTags;
  final List<String> preferredTags;

  UserPreferenceProfile({
    required this.userId,
    Map<String, double>? learnedWeights,
    List<String>? rejectedTags,
    List<String>? preferredTags,
  })  : learnedWeights = learnedWeights ?? {},
        rejectedTags = rejectedTags ?? [],
        preferredTags = preferredTags ?? [];

  factory UserPreferenceProfile.fromJson(Map<String, dynamic> json) =>
      _$UserPreferenceProfileFromJson(json);

  Map<String, dynamic> toJson() => _$UserPreferenceProfileToJson(this);
}

/// A segment of video for highlight analysis
@JsonSerializable()
class HighlightSegment {
  final String id;
  final Duration start;
  final Duration end;
  final Map<String, dynamic> metadata;

  HighlightSegment({
    String? id,
    required this.start,
    required this.end,
    Map<String, dynamic>? metadata,
  })  : id = id ?? _uuid.v4(),
        metadata = metadata ?? {};

  factory HighlightSegment.fromJson(Map<String, dynamic> json) =>
      _$HighlightSegmentFromJson(json);

  Map<String, dynamic> toJson() => _$HighlightSegmentToJson(this);

  Duration get duration => end - start;
}

/// Score for a highlight segment
@JsonSerializable()
class HighlightScore {
  final String segmentId;
  final double score;
  final Map<String, double> breakdown; // visual/audio/text component scores

  HighlightScore({
    required this.segmentId,
    required this.score,
    Map<String, double>? breakdown,
  }) : breakdown = breakdown ?? {};

  factory HighlightScore.fromJson(Map<String, dynamic> json) =>
      _$HighlightScoreFromJson(json);

  Map<String, dynamic> toJson() => _$HighlightScoreToJson(this);
}

/// Multimodal features extracted from video segments
@JsonSerializable()
class HighlightFeatures {
  final Map<String, List<double>> visualFeatures;
  final Map<String, List<double>> audioFeatures;
  final Map<String, List<double>> textFeatures;

  HighlightFeatures({
    Map<String, List<double>>? visualFeatures,
    Map<String, List<double>>? audioFeatures,
    Map<String, List<double>>? textFeatures,
  })  : visualFeatures = visualFeatures ?? {},
        audioFeatures = audioFeatures ?? {},
        textFeatures = textFeatures ?? {};

  factory HighlightFeatures.fromJson(Map<String, dynamic> json) =>
      _$HighlightFeaturesFromJson(json);

  Map<String, dynamic> toJson() => _$HighlightFeaturesToJson(this);
}

/// Transcript data from speech recognition
@JsonSerializable()
class TranscriptData {
  final List<TranscriptToken> tokens;

  TranscriptData({List<TranscriptToken>? tokens}) : tokens = tokens ?? [];

  factory TranscriptData.fromJson(Map<String, dynamic> json) =>
      _$TranscriptDataFromJson(json);

  Map<String, dynamic> toJson() => _$TranscriptDataToJson(this);
}

/// A single token in the transcript
@JsonSerializable()
class TranscriptToken {
  final Duration start;
  final Duration end;
  final String text;

  const TranscriptToken({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptToken.fromJson(Map<String, dynamic> json) =>
      _$TranscriptTokenFromJson(json);

  Map<String, dynamic> toJson() => _$TranscriptTokenToJson(this);
}
