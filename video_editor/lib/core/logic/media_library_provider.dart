import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/media_library_service.dart';

/// Provider for the media library service
final mediaLibraryServiceProvider = Provider<MediaLibraryService>((ref) {
  return MediaLibraryService(FFmpegVideoEngine());
});

/// State notifier for media library
class MediaLibraryNotifier extends StateNotifier<List<MediaItem>> {
  final MediaLibraryService _service;
  final Set<String> _hydrating = <String>{};

  MediaLibraryNotifier(this._service) : super([]);

  /// Import a single file
  Future<MediaItem?> importFile(String filePath) async {
    try {
      final item = await _service.importFile(filePath);
      state = [...state, item];
      return item;
    } on UnsupportedFileFormatException catch (e) {
      // Notify user about unsupported format
      debugPrint('Error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error importing file: $e');
      return null;
    }
  }

  /// Import multiple files
  Future<List<MediaItem>> importFiles(List<String> filePaths) async {
    final items = await _service.importFiles(filePaths);
    state = [...state, ...items];
    return items;
  }

  /// Remove an item
  Future<void> removeItem(String itemId) async {
    await _service.removeItem(itemId);
    state = state.where((item) => item.id != itemId).toList();
  }

  /// Get filtered items
  List<MediaItem> getItems({MediaType? filter}) {
    if (filter == null) return state;
    return state.where((item) => item.type == filter).toList();
  }

  /// Update an item
  void updateItem(MediaItem updatedItem) {
    _service.updateItem(updatedItem);
    state = state.map((item) {
      return item.id == updatedItem.id ? updatedItem : item;
    }).toList();
  }

  /// Replace all items
  void replaceAll(List<MediaItem> items) {
    _service.setItems(items);
    state = List<MediaItem>.from(items);
  }

  /// Load items from a project file
  void loadItems(List<MediaItem> items) {
    replaceAll(items);
    // Thumbnails are not serialized; refresh metadata in the background.
    Future.microtask(() => hydrateMissingMetadata());
  }

  /// Re-hydrate loaded items (thumbnails/durations/metadata) after project load.
  /// Returns the number of missing files detected.
  Future<int> hydrateMissingMetadata({int concurrency = 2}) async {
    final snapshot = List<MediaItem>.from(state);
    final missing = <String>[];
    final queue = <MediaItem>[];
    for (final item in snapshot) {
      if (_hydrating.contains(item.id)) continue;
      final file = File(item.filePath);
      if (!file.existsSync()) {
        missing.add(item.filePath);
        continue;
      }
      final needsThumbnail =
          (item.type == MediaType.video || item.type == MediaType.image) &&
              item.thumbnail == null;
      final needsDuration = item.duration == Duration.zero;
      final needsInfo = (item.type == MediaType.video && item.videoInfo == null) ||
          (item.type == MediaType.audio && item.audioInfo == null);
      if (needsThumbnail || needsDuration || needsInfo) {
        queue.add(item);
      }
    }

    Future<void> worker(MediaItem item) async {
      _hydrating.add(item.id);
      try {
        final hydrated = await _service.hydrateItem(item);
        // Update only if still present.
        if (state.any((i) => i.id == hydrated.id)) {
          updateItem(hydrated);
        }
      } finally {
        _hydrating.remove(item.id);
      }
    }

    final pool = <Future<void>>[];
    for (final item in queue) {
      pool.add(worker(item));
      if (pool.length >= concurrency) {
        await pool.removeAt(0);
      }
    }
    await Future.wait(pool);
    return missing.length;
  }

  /// Clear all items
  void clear() {
    _service.clear();
    state = [];
  }

  /// Get item counts by type
  Map<MediaType, int> getItemCounts() {
    return _service.getItemCounts();
  }
}

/// Provider for media library state
final mediaLibraryProvider =
    StateNotifierProvider<MediaLibraryNotifier, List<MediaItem>>((ref) {
  final service = ref.watch(mediaLibraryServiceProvider);
  return MediaLibraryNotifier(service);
});

/// Provider for Suno generation placeholders shown in the media library.
final sunoGeneratingProvider = StateProvider<List<String>>((ref) {
  return <String>[];
});

/// Provider for filtered media items (videos only)
final videoItemsProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(mediaLibraryProvider);
  return items.where((item) => item.type == MediaType.video).toList();
});

/// Provider for filtered media items (audio only)
final audioItemsProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(mediaLibraryProvider);
  return items.where((item) => item.type == MediaType.audio).toList();
});

/// Provider for filtered media items (images only)
final imageItemsProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(mediaLibraryProvider);
  return items.where((item) => item.type == MediaType.image).toList();
});

/// Provider for item counts
final mediaLibraryCountsProvider = Provider<Map<MediaType, int>>((ref) {
  final items = ref.watch(mediaLibraryProvider);
  final counts = <MediaType, int>{
    MediaType.video: 0,
    MediaType.audio: 0,
    MediaType.image: 0,
  };

  for (final item in items) {
    counts[item.type] = (counts[item.type] ?? 0) + 1;
  }

  return counts;
});
