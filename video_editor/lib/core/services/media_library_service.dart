import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:video_editor/core/engines/video_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/utils/file_validator.dart';

/// Exception thrown when a file format is not supported
class UnsupportedFileFormatException implements Exception {
  final String filePath;
  final String message;

  UnsupportedFileFormatException(this.filePath)
      : message = 'Unsupported file format: ${path.basename(filePath)}';

  @override
  String toString() => message;
}

/// Service for managing media library
class MediaLibraryService {
  static const _fallbackDuration = Duration(seconds: 5);
  final VideoEngine _videoEngine;
  final List<MediaItem> _items = [];

  MediaLibraryService(this._videoEngine);

  /// Get all media items
  List<MediaItem> get items => List.unmodifiable(_items);

  /// Import a single file into the media library
  Future<MediaItem> importFile(String filePath) async {
    // Validate file exists
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    // Validate file format
    if (!FileValidator.isSupportedFile(filePath)) {
      throw UnsupportedFileFormatException(filePath);
    }

    final mediaType = FileValidator.getMediaType(filePath)!;
    final fileName = path.basename(filePath);

    // Get metadata for supported media types
    Duration duration = Duration.zero;
    Uint8List? thumbnail;
    VideoInfo? videoInfo;
    AudioInfo? audioInfo;
    if (mediaType == MediaType.video) {
      videoInfo = await _safeVideoInfo(filePath);
      duration = videoInfo?.duration ?? Duration.zero;
      if (duration == Duration.zero) {
        duration = _fallbackDuration;
      }
      thumbnail = await _safeThumbnail(filePath);
    } else if (mediaType == MediaType.audio) {
      audioInfo = await _safeAudioInfo(filePath);
      duration = audioInfo?.duration ?? Duration.zero;
      if (duration == Duration.zero) {
        duration = _fallbackDuration;
      }
    } else if (mediaType == MediaType.image) {
      duration = _fallbackDuration;
      try {
        thumbnail = await file.readAsBytes();
      } catch (_) {
        // Ignore thumbnail failures.
      }
    }

    // Create media item with actual duration
    final mediaItem = MediaItem(
      name: fileName,
      filePath: filePath,
      type: mediaType,
      duration: duration,
      videoInfo: videoInfo,
      audioInfo: audioInfo,
      thumbnail: thumbnail,
    );

    _items.add(mediaItem);
    return mediaItem;
  }

  Future<VideoInfo?> _safeVideoInfo(String filePath) async {
    try {
      return await _videoEngine.getVideoInfo(filePath);
    } catch (e) {
      debugPrint('Error getting video info for $filePath: $e');
      return null;
    }
  }

  Future<AudioInfo?> _safeAudioInfo(String filePath) async {
    try {
      return await _videoEngine.getAudioInfo(filePath);
    } catch (e) {
      debugPrint('Error getting audio info for $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _safeThumbnail(String filePath) async {
    try {
      final bytes = await _videoEngine.generateThumbnail(
        filePath,
        const Duration(milliseconds: 500),
      );
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      debugPrint('Error generating thumbnail for $filePath: $e');
      return null;
    }
  }

  /// Re-hydrate a loaded media item with runtime-only metadata.
  ///
  /// Notes:
  /// - `MediaItem.thumbnail` is not serialized in project files.
  /// - Some media metadata can be missing or stale after load.
  /// This preserves the item's `id` while refreshing duration/info/thumbnail when possible.
  Future<MediaItem> hydrateItem(MediaItem item) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      return item;
    }

    Duration duration = item.duration;
    Uint8List? thumbnail = item.thumbnail;
    VideoInfo? videoInfo = item.videoInfo;
    AudioInfo? audioInfo = item.audioInfo;

    if (item.type == MediaType.video) {
      videoInfo ??= await _safeVideoInfo(item.filePath);
      duration = videoInfo?.duration ?? duration;
      if (duration == Duration.zero) duration = _fallbackDuration;
      if (thumbnail == null) {
        thumbnail = await _safeThumbnail(item.filePath);
      }
    } else if (item.type == MediaType.audio) {
      audioInfo ??= await _safeAudioInfo(item.filePath);
      duration = audioInfo?.duration ?? duration;
      if (duration == Duration.zero) duration = _fallbackDuration;
    } else if (item.type == MediaType.image) {
      if (duration == Duration.zero) duration = _fallbackDuration;
      if (thumbnail == null) {
        try {
          thumbnail = await file.readAsBytes();
        } catch (_) {
          // Ignore thumbnail failures.
        }
      }
    }

    return item.copyWith(
      duration: duration,
      videoInfo: videoInfo,
      audioInfo: audioInfo,
      thumbnail: thumbnail,
    );
  }

  /// Import multiple files into the media library
  Future<List<MediaItem>> importFiles(List<String> filePaths) async {
    final importedItems = <MediaItem>[];
    final errors = <String, Exception>{};

    for (final filePath in filePaths) {
      try {
        final item = await importFile(filePath);
        importedItems.add(item);
      } catch (e) {
        errors[filePath] = e is Exception ? e : Exception(e.toString());
      }
    }

    return importedItems;
  }

  /// Get items filtered by media type
  List<MediaItem> getItems({MediaType? filter}) {
    if (filter == null) return items;
    return _items.where((item) => item.type == filter).toList();
  }

  /// Remove an item from the library
  Future<void> removeItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
  }

  /// Get a specific item by ID
  MediaItem? getItem(String itemId) {
    try {
      return _items.firstWhere((item) => item.id == itemId);
    } catch (_) {
      return null;
    }
  }

  /// Update an existing media item
  void updateItem(MediaItem updatedItem) {
    final index = _items.indexWhere((item) => item.id == updatedItem.id);
    if (index != -1) {
      _items[index] = updatedItem;
    }
  }

  /// Clear all items from the library
  void clear() {
    _items.clear();
  }

  /// Replace all items in the library
  void setItems(List<MediaItem> items) {
    _items
      ..clear()
      ..addAll(items);
  }

  /// Get the count of items by type
  Map<MediaType, int> getItemCounts() {
    final counts = <MediaType, int>{
      MediaType.video: 0,
      MediaType.audio: 0,
      MediaType.image: 0,
    };

    for (final item in _items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }

    return counts;
  }
}
