// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'highlight.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HighlightPattern _$HighlightPatternFromJson(Map<String, dynamic> json) =>
    HighlightPattern(
      id: json['id'] as String,
      name: json['name'] as String,
      weights: (json['weights'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
      minGapSeconds: (json['minGapSeconds'] as num?)?.toInt() ?? 5,
      diversityWeight: (json['diversityWeight'] as num?)?.toDouble() ?? 0.3,
      paceFactor: (json['paceFactor'] as num?)?.toDouble() ?? 1.0,
    );

Map<String, dynamic> _$HighlightPatternToJson(HighlightPattern instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'weights': instance.weights,
      'minGapSeconds': instance.minGapSeconds,
      'diversityWeight': instance.diversityWeight,
      'paceFactor': instance.paceFactor,
    };

HighlightPreferences _$HighlightPreferencesFromJson(
  Map<String, dynamic> json,
) => HighlightPreferences(
  modalityWeights:
      (json['modalityWeights'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ) ??
      const {'visual': 0.4, 'audio': 0.4, 'text': 0.2},
  diversityWeight: (json['diversityWeight'] as num?)?.toDouble() ?? 0.3,
  minGapSeconds: (json['minGapSeconds'] as num?)?.toInt() ?? 5,
  preferHighMotion: json['preferHighMotion'] as bool? ?? true,
  preferFaces: json['preferFaces'] as bool? ?? true,
  preferSpeechPeaks: json['preferSpeechPeaks'] as bool? ?? true,
);

Map<String, dynamic> _$HighlightPreferencesToJson(
  HighlightPreferences instance,
) => <String, dynamic>{
  'modalityWeights': instance.modalityWeights,
  'diversityWeight': instance.diversityWeight,
  'minGapSeconds': instance.minGapSeconds,
  'preferHighMotion': instance.preferHighMotion,
  'preferFaces': instance.preferFaces,
  'preferSpeechPeaks': instance.preferSpeechPeaks,
};

UserPreferenceProfile _$UserPreferenceProfileFromJson(
  Map<String, dynamic> json,
) => UserPreferenceProfile(
  userId: json['userId'] as String,
  learnedWeights: (json['learnedWeights'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, (e as num).toDouble()),
  ),
  rejectedTags: (json['rejectedTags'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  preferredTags: (json['preferredTags'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$UserPreferenceProfileToJson(
  UserPreferenceProfile instance,
) => <String, dynamic>{
  'userId': instance.userId,
  'learnedWeights': instance.learnedWeights,
  'rejectedTags': instance.rejectedTags,
  'preferredTags': instance.preferredTags,
};

HighlightSegment _$HighlightSegmentFromJson(Map<String, dynamic> json) =>
    HighlightSegment(
      id: json['id'] as String?,
      start: Duration(microseconds: (json['start'] as num).toInt()),
      end: Duration(microseconds: (json['end'] as num).toInt()),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$HighlightSegmentToJson(HighlightSegment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'start': instance.start.inMicroseconds,
      'end': instance.end.inMicroseconds,
      'metadata': instance.metadata,
    };

HighlightScore _$HighlightScoreFromJson(Map<String, dynamic> json) =>
    HighlightScore(
      segmentId: json['segmentId'] as String,
      score: (json['score'] as num).toDouble(),
      breakdown: (json['breakdown'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
    );

Map<String, dynamic> _$HighlightScoreToJson(HighlightScore instance) =>
    <String, dynamic>{
      'segmentId': instance.segmentId,
      'score': instance.score,
      'breakdown': instance.breakdown,
    };

HighlightFeatures _$HighlightFeaturesFromJson(Map<String, dynamic> json) =>
    HighlightFeatures(
      visualFeatures: (json['visualFeatures'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        ),
      ),
      audioFeatures: (json['audioFeatures'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        ),
      ),
      textFeatures: (json['textFeatures'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          (e as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        ),
      ),
    );

Map<String, dynamic> _$HighlightFeaturesToJson(HighlightFeatures instance) =>
    <String, dynamic>{
      'visualFeatures': instance.visualFeatures,
      'audioFeatures': instance.audioFeatures,
      'textFeatures': instance.textFeatures,
    };

TranscriptData _$TranscriptDataFromJson(Map<String, dynamic> json) =>
    TranscriptData(
      tokens: (json['tokens'] as List<dynamic>?)
          ?.map((e) => TranscriptToken.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TranscriptDataToJson(TranscriptData instance) =>
    <String, dynamic>{'tokens': instance.tokens};

TranscriptToken _$TranscriptTokenFromJson(Map<String, dynamic> json) =>
    TranscriptToken(
      start: Duration(microseconds: (json['start'] as num).toInt()),
      end: Duration(microseconds: (json['end'] as num).toInt()),
      text: json['text'] as String,
    );

Map<String, dynamic> _$TranscriptTokenToJson(TranscriptToken instance) =>
    <String, dynamic>{
      'start': instance.start.inMicroseconds,
      'end': instance.end.inMicroseconds,
      'text': instance.text,
    };
