import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'timeline.dart';

part 'timeline_group.g.dart';

const _uuid = Uuid();

/// Represents a timeline group - a named collection containing a timeline
@JsonSerializable()
class TimelineGroup {
  final String id;
  final String name;
  final Timeline timeline;

  TimelineGroup({
    String? id,
    required this.name,
    Timeline? timeline,
  })  : id = id ?? _uuid.v4(),
        timeline = timeline ?? Timeline();

  factory TimelineGroup.fromJson(Map<String, dynamic> json) =>
      _$TimelineGroupFromJson(json);

  Map<String, dynamic> toJson() => _$TimelineGroupToJson(this);

  TimelineGroup copyWith({
    String? name,
    Timeline? timeline,
  }) {
    return TimelineGroup(
      id: id,
      name: name ?? this.name,
      timeline: timeline ?? this.timeline,
    );
  }
}
