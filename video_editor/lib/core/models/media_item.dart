import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import 'enums.dart';
import 'media_info.dart';

part 'media_item.g.dart';

const _uuid = Uuid();

/// Represents a media file in the media library
@JsonSerializable()
class MediaItem {
  final String id;
  final String name;
  final String filePath;
  final MediaType type;
  final Duration duration;
  final VideoInfo? videoInfo;
  final AudioInfo? audioInfo;

  @JsonKey(includeToJson: false, includeFromJson: false)
  final Uint8List? thumbnail;

  MediaItem({
    String? id,
    required this.name,
    required this.filePath,
    required this.type,
    required this.duration,
    this.videoInfo,
    this.audioInfo,
    this.thumbnail,
  }) : id = id ?? _uuid.v4();

  factory MediaItem.fromJson(Map<String, dynamic> json) =>
      _$MediaItemFromJson(json);

  Map<String, dynamic> toJson() => _$MediaItemToJson(this);

  MediaItem copyWith({
    String? name,
    String? filePath,
    MediaType? type,
    Duration? duration,
    VideoInfo? videoInfo,
    AudioInfo? audioInfo,
    Uint8List? thumbnail,
  }) {
    return MediaItem(
      id: id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      videoInfo: videoInfo ?? this.videoInfo,
      audioInfo: audioInfo ?? this.audioInfo,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }
}
