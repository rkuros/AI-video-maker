import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:video_editor/core/services/multimodal_feature_scorer.dart';

class HighlightFeatureCache {
  HighlightFeatureCache._();

  static final HighlightFeatureCache instance = HighlightFeatureCache._();

  static const int cacheVersion = 1;
  static bool _installedExitHandlers = false;

  Directory? _dir;
  final _mem = <String, SegmentFeatures>{};
  final _lru = <String>[];
  static const int _maxMemoryEntries = 512;

  Directory _ensureDir() {
    final existing = _dir;
    if (existing != null) return existing;
    final created = Directory(
      '${Directory.systemTemp.path}/video_editor_highlight_cache_${pid}',
    );
    created.createSync(recursive: true);
    _dir = created;
    return created;
  }

  static int _fnv1a64(List<int> data) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final b in data) {
      hash ^= b & 0xff;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }

  String buildKey({
    required String videoPath,
    required DateTime fileMtime,
    required int fileSize,
    required Duration startTime,
    required Duration endTime,
    required Map<String, Object?> params,
  }) {
    final payload = <String, Object?>{
      'v': cacheVersion,
      'path': videoPath,
      'mtimeMs': fileMtime.millisecondsSinceEpoch,
      'size': fileSize,
      'startUs': startTime.inMicroseconds,
      'endUs': endTime.inMicroseconds,
      'p': params,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final h = _fnv1a64(bytes);
    return h.toRadixString(16).padLeft(16, '0');
  }

  File _fileForKey(String key) {
    final dir = _ensureDir();
    return File('${dir.path}/$key.json');
  }

  Future<SegmentFeatures?> getFeatures(String key) async {
    final inMem = _mem[key];
    if (inMem != null) {
      _touch(key);
      return inMem;
    }

    final file = _fileForKey(key);
    if (!file.existsSync()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['v'] != cacheVersion) return null;
      final f = data['features'] as Map<String, dynamic>?;
      if (f == null) return null;
      final features = SegmentFeatures(
        motionIntensity: (f['motionIntensity'] as num).toDouble(),
        sceneChanges: (f['sceneChanges'] as num).toInt(),
        faceCount: (f['faceCount'] as num).toDouble(),
        hasSmiles: (f['hasSmiles'] as bool?) ?? false,
        aestheticScore: (f['aestheticScore'] as num).toDouble(),
        volumeLevel: (f['volumeLevel'] as num).toDouble(),
        energyLevel: (f['energyLevel'] as num).toDouble(),
        hasSpeech: (f['hasSpeech'] as bool?) ?? false,
        beatCount: (f['beatCount'] as num).toInt(),
        hasText: (f['hasText'] as bool?) ?? false,
        keywordScore: (f['keywordScore'] as num).toDouble(),
      );
      _putMem(key, features);
      return features;
    } catch (_) {
      return null;
    }
  }

  Future<void> putFeatures(String key, SegmentFeatures features) async {
    _putMem(key, features);
    final file = _fileForKey(key);
    final tmp = File('${file.path}.tmp');
    final data = <String, Object?>{
      'v': cacheVersion,
      'features': <String, Object?>{
        'motionIntensity': features.motionIntensity,
        'sceneChanges': features.sceneChanges,
        'faceCount': features.faceCount,
        'hasSmiles': features.hasSmiles,
        'aestheticScore': features.aestheticScore,
        'volumeLevel': features.volumeLevel,
        'energyLevel': features.energyLevel,
        'hasSpeech': features.hasSpeech,
        'beatCount': features.beatCount,
        'hasText': features.hasText,
        'keywordScore': features.keywordScore,
      },
    };
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }

  void _touch(String key) {
    _lru.remove(key);
    _lru.add(key);
  }

  void _putMem(String key, SegmentFeatures features) {
    _mem[key] = features;
    _touch(key);
    while (_lru.length > _maxMemoryEntries) {
      final evict = _lru.removeAt(0);
      _mem.remove(evict);
    }
  }

  Future<void> clear() async {
    _mem.clear();
    _lru.clear();
    final dir = _dir;
    _dir = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static void installExitHandlers() {
    if (_installedExitHandlers) return;
    _installedExitHandlers = true;

    if (!Platform.isWindows) {
      Future<void> handleSignal(ProcessSignal signal) async {
        await instance.clear();
        exit(0);
      }

      unawaited(ProcessSignal.sigterm.watch().first.then(handleSignal));
      unawaited(ProcessSignal.sigint.watch().first.then(handleSignal));
    }
  }
}
