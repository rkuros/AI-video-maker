import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';
import 'package:video_editor/core/engines/export_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/models/enums.dart' as enums;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Playback speed options
enum PlaybackSpeed {
  x025(0.25, '0.25x'),
  x05(0.5, '0.5x'),
  x1(1.0, '1x'),
  x2(2.0, '2x'),
  x4(4.0, '4x');

  const PlaybackSpeed(this.value, this.label);
  final double value;
  final String label;
}

/// Preview state class
class PreviewState {
  final Player? player;
  final VideoController? videoController;
  final Player? comparePlayer;
  final VideoController? compareVideoController;
  final bool isPlaying;
  final bool isLoading;
  final Duration currentPosition;
  final Duration duration;
  final PlaybackSpeed speed;
  final String? currentVideoPath;
  final String? playbackVideoPath;
  final String? error;
  final bool isEffectPreview;
  final String? effectPreviewPath;
  final String? effectOriginalPath;
  final Duration effectClipSourceStart;
  final Duration effectClipDuration;
  final String? timelinePreviewPath;
  final bool isTimelineStreaming;
  final Duration timelineStreamStartOffset;
  final enums.PreviewQualityPreset timelinePreviewPreset;

  const PreviewState({
    this.player,
    this.videoController,
    this.comparePlayer,
    this.compareVideoController,
    this.isPlaying = false,
    this.isLoading = false,
    this.currentPosition = Duration.zero,
    this.duration = Duration.zero,
    this.speed = PlaybackSpeed.x1,
    this.currentVideoPath,
    this.playbackVideoPath,
    this.error,
    this.isEffectPreview = false,
    this.effectPreviewPath,
    this.effectOriginalPath,
    this.effectClipSourceStart = Duration.zero,
    this.effectClipDuration = Duration.zero,
    this.timelinePreviewPath,
    this.isTimelineStreaming = false,
    this.timelineStreamStartOffset = Duration.zero,
    this.timelinePreviewPreset = enums.PreviewQualityPreset.quick,
  });

  static const Object _unset = Object();

  PreviewState copyWith({
    Object? player = _unset,
    Object? videoController = _unset,
    Object? comparePlayer = _unset,
    Object? compareVideoController = _unset,
    bool? isPlaying,
    bool? isLoading,
    Duration? currentPosition,
    Duration? duration,
    PlaybackSpeed? speed,
    Object? currentVideoPath = _unset,
    Object? playbackVideoPath = _unset,
    Object? error = _unset,
    bool? isEffectPreview,
    Object? effectPreviewPath = _unset,
    Object? effectOriginalPath = _unset,
    Duration? effectClipSourceStart,
    Duration? effectClipDuration,
    Object? timelinePreviewPath = _unset,
    bool? isTimelineStreaming,
    Duration? timelineStreamStartOffset,
    enums.PreviewQualityPreset? timelinePreviewPreset,
  }) {
    return PreviewState(
      player: identical(player, _unset) ? this.player : player as Player?,
      videoController: identical(videoController, _unset)
          ? this.videoController
          : videoController as VideoController?,
      comparePlayer: identical(comparePlayer, _unset)
          ? this.comparePlayer
          : comparePlayer as Player?,
      compareVideoController: identical(compareVideoController, _unset)
          ? this.compareVideoController
          : compareVideoController as VideoController?,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      currentPosition: currentPosition ?? this.currentPosition,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      currentVideoPath: identical(currentVideoPath, _unset)
          ? this.currentVideoPath
          : currentVideoPath as String?,
      playbackVideoPath: identical(playbackVideoPath, _unset)
          ? this.playbackVideoPath
          : playbackVideoPath as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      isEffectPreview: isEffectPreview ?? this.isEffectPreview,
      effectPreviewPath: identical(effectPreviewPath, _unset)
          ? this.effectPreviewPath
          : effectPreviewPath as String?,
      effectOriginalPath: identical(effectOriginalPath, _unset)
          ? this.effectOriginalPath
          : effectOriginalPath as String?,
      effectClipSourceStart:
          effectClipSourceStart ?? this.effectClipSourceStart,
      effectClipDuration: effectClipDuration ?? this.effectClipDuration,
      timelinePreviewPath: identical(timelinePreviewPath, _unset)
          ? this.timelinePreviewPath
          : timelinePreviewPath as String?,
      isTimelineStreaming: isTimelineStreaming ?? this.isTimelineStreaming,
      timelineStreamStartOffset:
          timelineStreamStartOffset ?? this.timelineStreamStartOffset,
      timelinePreviewPreset:
          timelinePreviewPreset ?? this.timelinePreviewPreset,
    );
  }
}

/// Preview notifier for state management
class PreviewNotifier extends StateNotifier<PreviewState> {
  PreviewNotifier() : super(const PreviewState());

  final FFmpegVideoEngine _videoEngine = FFmpegVideoEngine();
  final ExportEngine _exportEngine = ExportEngine();
  final List<String> _effectPreviewTempPaths = [];
  final List<String> _previewProxyTempPaths = [];

  Player? _player;
  VideoController? _videoController;
  Player? _comparePlayer;
  VideoController? _compareVideoController;
  Timer? _effectSyncTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  HlsPreviewSession? _hlsSession;
  final Map<String, HlsPreviewSession> _hlsCache = {};
  static const int _maxCachedHlsStreams = 2;
  Timer? _seekDebounce;
  Duration? _pendingSeek;
  Timeline? _lastStreamTimeline;
  List<MediaItem>? _lastStreamMediaLibrary;

  bool _returnWasStreaming = false;
  bool _returnWasPlaying = false;
  Duration _returnTimelinePosition = Duration.zero;
  Timeline? _returnStreamTimeline;
  List<MediaItem>? _returnStreamMediaLibrary;
  String? _returnVideoPath;
  Duration _returnVideoPosition = Duration.zero;

  static String get _previewLogPath =>
      '${Directory.systemTemp.path}/video_editor_preview.log';

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    try {
      final now = DateTime.now().toIso8601String();
      final buffer = StringBuffer('[$now] $message\n');
      if (error != null) buffer.write('error: $error\n');
      if (stackTrace != null) buffer.write('$stackTrace\n');
      buffer.write('\n');
      File(_previewLogPath).writeAsStringSync(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  void _ensurePlayerInitialized() {
    if (_player != null && _videoController != null) return;
    final player = Player();
    final videoController = VideoController(player);

    _playingSub = player.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    _positionSub = player.stream.position.listen((position) {
      state = state.copyWith(currentPosition: position);
    });
    _durationSub = player.stream.duration.listen((duration) {
      state = state.copyWith(duration: duration ?? Duration.zero);
    });

    _player = player;
    _videoController = videoController;
    state = state.copyWith(player: player, videoController: videoController);
  }

  void _ensureComparePlayerInitialized() {
    if (_comparePlayer != null && _compareVideoController != null) return;
    final player = Player();
    final videoController = VideoController(player);
    _comparePlayer = player;
    _compareVideoController = videoController;
    state = state.copyWith(
      comparePlayer: player,
      compareVideoController: videoController,
    );
  }

  Future<void> _stopEffectPreview() async {
    _effectSyncTimer?.cancel();
    _effectSyncTimer = null;
    try {
      await _comparePlayer?.stop();
    } catch (_) {}
    _comparePlayer?.dispose();
    _comparePlayer = null;
    _compareVideoController = null;

    await _cleanupEffectPreviewTemps();

    state = state.copyWith(
      isEffectPreview: false,
      effectPreviewPath: null,
      effectOriginalPath: null,
      effectClipSourceStart: Duration.zero,
      effectClipDuration: Duration.zero,
      comparePlayer: null,
      compareVideoController: null,
    );
  }

  Future<void> _cleanupEffectPreviewTemps() async {
    final paths = List<String>.from(_effectPreviewTempPaths);
    _effectPreviewTempPaths.clear();
    for (final p in paths) {
      try {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _cleanupPreviewProxyTemps() async {
    final paths = List<String>.from(_previewProxyTempPaths);
    _previewProxyTempPaths.clear();
    for (final p in paths) {
      try {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  String _hlsCacheKey({
    required Timeline timeline,
    required enums.PreviewQualityPreset preset,
    required Duration startPosition,
  }) {
    // Cache is only valid while the timeline is unchanged; invalidateTimelinePreview clears it.
    // Include startPosition for seek/restart caching.
    final startMs = startPosition.inMilliseconds < 0
        ? 0
        : startPosition.inMilliseconds;
    return '${timeline.id}|${preset.name}|$startMs';
  }

  Future<void> clearTimelinePreviewCache() async {
    _seekDebounce?.cancel();
    _seekDebounce = null;
    _pendingSeek = null;
    _hlsSession = null;
    _lastStreamTimeline = null;
    _lastStreamMediaLibrary = null;

    final sessions = List<HlsPreviewSession>.from(_hlsCache.values);
    _hlsCache.clear();
    for (final s in sessions) {
      try {
        await s.stop();
      } catch (_) {}
    }

    state = state.copyWith(
      isTimelineStreaming: false,
      timelinePreviewPath: null,
      currentVideoPath: null,
      playbackVideoPath: null,
      timelineStreamStartOffset: Duration.zero,
    );
  }

  Future<void> _detachTimelineStream() async {
    _seekDebounce?.cancel();
    _seekDebounce = null;
    _pendingSeek = null;

    _hlsSession = null;
    _lastStreamTimeline = null;
    _lastStreamMediaLibrary = null;
  }

  void _scheduleTimelineStreamRestart(
    Duration timelinePosition, {
    required bool autoPlay,
  }) {
    _pendingSeek = timelinePosition;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 250), () {
      final target = _pendingSeek;
      _pendingSeek = null;
      if (target == null) return;
      _restartTimelineStreamAt(target, autoPlay: autoPlay);
    });
  }

  Future<void> _restartTimelineStreamAt(
    Duration timelinePosition, {
    required bool autoPlay,
  }) async {
    final timeline = _lastStreamTimeline;
    final mediaLibrary = _lastStreamMediaLibrary;
    if (timeline == null || mediaLibrary == null) return;
    try {
      await loadTimelinePreview(
        timeline,
        mediaLibrary,
        preset: state.timelinePreviewPreset,
        startPosition: timelinePosition,
      );
      if (autoPlay) {
        await play();
      }
    } catch (e, st) {
      _log('_restartTimelineStreamAt failed', error: e, stackTrace: st);
    }
  }

  Future<bool> _waitForHlsReady(
    String playlistPath, {
    required Duration timeout,
    void Function(Duration elapsed)? onTick,
  }) async {
    final startedAt = DateTime.now();
    while (true) {
      final elapsed = DateTime.now().difference(startedAt);
      onTick?.call(elapsed);
      if (elapsed >= timeout) {
        return false;
      }

      try {
        final f = File(playlistPath);
        if (await f.exists()) {
          final text = await f.readAsString();
          // A ready playlist typically contains at least one media segment entry.
          if (text.contains('#EXTINF') || text.contains('.m4s')) {
            return true;
          }
        }
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, dynamic>?> _probeVideoStream(String filePath) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=codec_name,pix_fmt,profile,color_primaries,color_transfer,color_space',
        '-of',
        'json',
        filePath,
      ]);
      if (result.exitCode != 0) return null;
      final decoded = json.decode(result.stdout as String);
      if (decoded is! Map<String, dynamic>) return null;
      final streams = decoded['streams'];
      if (streams is! List || streams.isEmpty) return null;
      final stream = streams.first;
      if (stream is! Map<String, dynamic>) return null;
      return stream;
    } catch (_) {
      return null;
    }
  }

  bool _shouldProxyForMacOS(Map<String, dynamic> stream) {
    final codec = (stream['codec_name'] as String?)?.toLowerCase();
    final pixFmt = (stream['pix_fmt'] as String?)?.toLowerCase();
    final transfer = (stream['color_transfer'] as String?)?.toLowerCase();
    final primaries = (stream['color_primaries'] as String?)?.toLowerCase();

    final isHevc = codec == 'hevc' || codec == 'h265';
    final is10Bit = pixFmt != null && pixFmt.contains('10');
    final isHdr =
        transfer == 'arib-std-b67' ||
        transfer == 'smpte2084' ||
        (primaries != null && primaries.contains('bt2020'));

    return isHevc && (is10Bit || isHdr);
  }

  Future<String> _ensurePreviewPlayable(String filePath) async {
    if (!Platform.isMacOS) return filePath;

    final stream = await _probeVideoStream(filePath);
    if (stream == null) return filePath;

    if (!_shouldProxyForMacOS(stream)) return filePath;

    final proxyPath = await _createTempOutputPath(suffix: 'proxy');
    _previewProxyTempPaths.add(proxyPath);

    _log(
      'Generating preview proxy',
      error: {'input': filePath, 'output': proxyPath, 'stream': stream},
    );

    // Try to use hardware encoder for faster proxy generation
    final hardwareEncoder = await _detectHardwareEncoder();
    final useHardware = hardwareEncoder != null;

    final args = [
      if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
      '-y',
      '-i',
      filePath,
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-vf',
      'scale=1280:-2:force_original_aspect_ratio=decrease,format=yuv420p',
      '-c:v',
      useHardware ? hardwareEncoder : 'libx264',
    ];

    if (useHardware) {
      // Hardware encoder - use bitrate
      // VideoToolbox works best with minimal settings
      args.addAll(['-b:v', '3M']);
    } else {
      // Software encoder - use CRF
      args.addAll(['-crf', '23', '-preset', 'veryfast']);
    }

    args.addAll([
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      proxyPath,
    ]);

    var result = await Process.run('ffmpeg', args);
    if (result.exitCode != 0 && Platform.isMacOS) {
      result = await Process.run(
        'ffmpeg',
        args.where((a) => a != 'videotoolbox' && a != '-hwaccel').toList(),
      );
    }

    if (result.exitCode != 0) {
      _log(
        'Failed to generate preview proxy',
        error: result.stderr ?? result.stdout,
      );
      return filePath;
    }

    return proxyPath;
  }

  // Cache for hardware encoder detection
  String? _cachedHardwareEncoder;
  bool _hardwareEncoderChecked = false;

  /// Detect hardware encoder (shared logic with ExportEngine)
  Future<String?> _detectHardwareEncoder() async {
    if (_hardwareEncoderChecked) {
      return _cachedHardwareEncoder;
    }

    _hardwareEncoderChecked = true;

    try {
      final result = await Process.run('ffmpeg', ['-hide_banner', '-encoders']);

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout as String;

      final encodersToTry = [
        'h264_videotoolbox',
        'h264_nvenc',
        'h264_qsv',
        'h264_vaapi',
      ];

      for (final encoder in encodersToTry) {
        if (output.contains(encoder)) {
          _cachedHardwareEncoder = encoder;
          return encoder;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Load and play a video
  Future<void> loadVideo(String filePath) async {
    _log('loadVideo start', error: filePath);
    state = state.copyWith(
      isPlaying: false,
      currentPosition: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
      error: null,
      isEffectPreview: false,
      effectPreviewPath: null,
      timelinePreviewPath: null,
      isTimelineStreaming: false,
      timelineStreamStartOffset: Duration.zero,
      currentVideoPath: null,
      playbackVideoPath: null,
    );

    try {
      await _detachTimelineStream();
      await _cleanupEffectPreviewTemps();
      await _cleanupPreviewProxyTemps();

      final playbackPath = await _ensurePreviewPlayable(filePath);

      _ensurePlayerInitialized();
      final player = _player!;
      await player.open(Media(playbackPath), play: false);
      await player.setRate(state.speed.value);

      // Update state
      state = state.copyWith(
        isLoading: false,
        currentVideoPath: filePath,
        playbackVideoPath: playbackPath,
        isEffectPreview: false,
        effectPreviewPath: null,
        timelinePreviewPath: null,
        isTimelineStreaming: false,
        timelineStreamStartOffset: Duration.zero,
        error: null,
      );
    } catch (e) {
      _log('loadVideo failed', error: e);
      state = state.copyWith(
        isPlaying: false,
        currentVideoPath: null,
        playbackVideoPath: null,
        duration: Duration.zero,
        isLoading: false,
        error: 'Failed to load video: $e',
      );
    }
  }

  /// Play the video
  Future<void> play() async {
    try {
      _ensurePlayerInitialized();
      _log('play()');
      await _player!.play();
      if (state.isEffectPreview && _comparePlayer != null) {
        await _comparePlayer!.play();
      }
    } catch (e, st) {
      _log('play() failed', error: e, stackTrace: st);
      state = state.copyWith(error: 'Failed to play: $e');
    }
  }

  /// Pause the video
  Future<void> pause() async {
    try {
      if (_player == null) return;
      _log('pause()');
      await _player!.pause();
      if (state.isEffectPreview && _comparePlayer != null) {
        await _comparePlayer!.pause();
      }
    } catch (e, st) {
      _log('pause() failed', error: e, stackTrace: st);
      state = state.copyWith(error: 'Failed to pause: $e');
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    if (state.isEffectPreview && _player != null && _comparePlayer != null) {
      final clipDuration = state.effectClipDuration;
      if (clipDuration > Duration.zero) {
        var pos = position;
        if (pos < Duration.zero) pos = Duration.zero;
        if (pos > clipDuration) pos = clipDuration;
        await _player!.seek(pos);
        await _comparePlayer!.seek(state.effectClipSourceStart + pos);
        return;
      }
    }
    if (state.isTimelineStreaming) {
      // Restart stream from the requested timeline position for seamless behavior.
      _scheduleTimelineStreamRestart(position, autoPlay: state.isPlaying);
      return;
    }

    // Update current position even if player is not initialized
    // This ensures the preview state reflects the playhead position
    state = state.copyWith(currentPosition: position);

    if (_player == null) return;
    await _player!.seek(position);
  }

  /// Set playback speed
  Future<void> setPlaybackSpeed(PlaybackSpeed speed) async {
    state = state.copyWith(speed: speed);
    if (_player == null) return;
    await _player!.setRate(speed.value);
    if (state.isEffectPreview && _comparePlayer != null) {
      await _comparePlayer!.setRate(speed.value);
    }
  }

  /// Unload current video
  Future<void> unloadVideo() async {
    await _detachTimelineStream();
    await _stopEffectPreview();

    state = state.copyWith(
      isPlaying: false,
      isLoading: false,
      currentPosition: Duration.zero,
      duration: Duration.zero,
      currentVideoPath: null,
      playbackVideoPath: null,
      error: null,
      isEffectPreview: false,
      effectPreviewPath: null,
      effectOriginalPath: null,
      effectClipSourceStart: Duration.zero,
      effectClipDuration: Duration.zero,
      timelinePreviewPath: null,
      isTimelineStreaming: false,
      timelineStreamStartOffset: Duration.zero,
      speed: state.speed,
    );

    if (_player != null) {
      try {
        await _player!.stop();
      } catch (_) {}
    }
    await _cleanupEffectPreviewTemps();
    await _cleanupPreviewProxyTemps();
  }

  Future<void> setTimelinePreviewPreset(
    enums.PreviewQualityPreset preset,
  ) async {
    if (preset == state.timelinePreviewPreset) return;

    final wasPlaying = state.isPlaying;
    final wasStreaming = state.isTimelineStreaming;
    final currentTimelinePosition = wasStreaming
        ? state.timelineStreamStartOffset + state.currentPosition
        : null;

    state = state.copyWith(
      timelinePreviewPreset: preset,
      timelinePreviewPath: null,
    );

    // If a timeline stream is active, restart it immediately at the current
    // timeline position so the new resolution/quality takes effect right away.
    if (wasStreaming &&
        _lastStreamTimeline != null &&
        _lastStreamMediaLibrary != null) {
      await loadTimelinePreview(
        _lastStreamTimeline!,
        _lastStreamMediaLibrary!,
        preset: preset,
        startPosition: currentTimelinePosition,
      );
      if (wasPlaying) {
        await play();
      }
      return;
    }

    // Otherwise, just stop any pending stream state; the next Play will start
    // with the new preset.
    await _detachTimelineStream();
    state = state.copyWith(
      isTimelineStreaming: false,
      timelineStreamStartOffset: Duration.zero,
    );
  }

  ExportSettings _settingsForTimelineStream({
    required enums.PreviewQualityPreset preset,
  }) {
    switch (preset) {
      case enums.PreviewQualityPreset.draft:
        return ExportSettings(
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r480p,
          quality: enums.Quality.low,
          frameRate: 12,
          videoPreset: 'ultrafast',
          audioSettings: const AudioSettings(bitrate: 96000),
        );
      case enums.PreviewQualityPreset.quick:
        return ExportSettings(
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r480p,
          quality: enums.Quality.low,
          frameRate: 15,
          videoPreset: 'ultrafast',
          audioSettings: const AudioSettings(bitrate: 96000),
        );
      case enums.PreviewQualityPreset.balanced:
        return ExportSettings(
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r720p,
          quality: enums.Quality.standard,
          frameRate: 24,
          videoPreset: 'veryfast',
          audioSettings: const AudioSettings(bitrate: 128000),
        );
      case enums.PreviewQualityPreset.standard:
        return ExportSettings(
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r720p,
          quality: enums.Quality.standard,
          frameRate: 30,
          videoPreset: 'medium',
          audioSettings: const AudioSettings(bitrate: 192000),
        );
    }
  }

  Future<void> generateEffectPreview(Clip clip, MediaItem mediaItem) async {
    if (clip.effects.isEmpty) return;
    if (mediaItem.filePath.isEmpty) return;

    try {
      // Save current playback context so we can restore on exit.
      _returnWasStreaming = state.isTimelineStreaming;
      _returnWasPlaying = state.isPlaying;
      _returnTimelinePosition = state.isTimelineStreaming
          ? state.timelineStreamStartOffset + state.currentPosition
          : Duration.zero;
      _returnStreamTimeline = _lastStreamTimeline;
      _returnStreamMediaLibrary = _lastStreamMediaLibrary;
      _returnVideoPath = state.currentVideoPath;
      _returnVideoPosition = state.currentPosition;

      state = state.copyWith(isLoading: true, error: null);

      await _detachTimelineStream();
      await pause();
      await _stopEffectPreview();

      // Render the selected clip segment with effects applied.
      final outputPath = await _createTempOutputPath(suffix: 'effect');
      _effectPreviewTempPaths.add(outputPath);
      await _videoEngine.renderClipWithEffects(
        mediaItem.filePath,
        outputPath,
        sourceStart: clip.sourceStart,
        duration: clip.sourceDuration > Duration.zero
            ? clip.sourceDuration
            : clip.duration,
        effects: clip.effects,
        inTransition: clip.inTransition,
        outTransition: clip.outTransition,
      );

      final clipDuration = clip.sourceDuration > Duration.zero
          ? clip.sourceDuration
          : clip.duration;

      _ensurePlayerInitialized();
      _ensureComparePlayerInitialized();

      await _player!.open(Media(outputPath), play: false);
      await _player!.setRate(state.speed.value);

      await _comparePlayer!.open(Media(mediaItem.filePath), play: false);
      await _comparePlayer!.setRate(state.speed.value);
      await _comparePlayer!.seek(clip.sourceStart);

      state = state.copyWith(
        isLoading: false,
        isEffectPreview: true,
        effectPreviewPath: outputPath,
        effectOriginalPath: mediaItem.filePath,
        effectClipSourceStart: clip.sourceStart,
        effectClipDuration: clipDuration,
        currentVideoPath: outputPath,
        playbackVideoPath: outputPath,
        timelinePreviewPath: null,
        isTimelineStreaming: false,
        timelineStreamStartOffset: Duration.zero,
        error: null,
      );

      _effectSyncTimer?.cancel();
      _effectSyncTimer = Timer.periodic(const Duration(milliseconds: 300), (
        _,
      ) async {
        if (!state.isEffectPreview || _player == null || _comparePlayer == null)
          return;
        final pos = _player!.state.position;
        final target = state.effectClipSourceStart + pos;
        final beforePos = _comparePlayer!.state.position;
        final drift = (beforePos - target).inMilliseconds.abs();
        if (drift > 150) {
          try {
            await _comparePlayer!.seek(target);
          } catch (_) {}
        }
        final d = state.effectClipDuration;
        if (d > Duration.zero && pos >= d) {
          try {
            await pause();
            await _player!.seek(Duration.zero);
            await _comparePlayer!.seek(state.effectClipSourceStart);
          } catch (_) {}
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to generate effect preview: $e',
      );
    }
  }

  /// Exit effect preview and return to original video
  Future<void> exitEffectPreview() async {
    if (!state.isEffectPreview) {
      return;
    }
    await _stopEffectPreview();

    // Restore previous playback context.
    if (_returnWasStreaming &&
        _returnStreamTimeline != null &&
        _returnStreamMediaLibrary != null) {
      await loadTimelinePreview(
        _returnStreamTimeline!,
        _returnStreamMediaLibrary!,
        preset: state.timelinePreviewPreset,
        startPosition: _returnTimelinePosition,
      );
      if (_returnWasPlaying) {
        await play();
      }
      return;
    }

    if (_returnVideoPath != null) {
      await loadVideo(_returnVideoPath!);
      if (_returnVideoPosition > Duration.zero) {
        await seekTo(_returnVideoPosition);
      }
      if (_returnWasPlaying) {
        await play();
      }
      return;
    }
  }

  Future<void> loadTimelinePreview(
    Timeline timeline,
    List<MediaItem> mediaLibrary, {
    enums.PreviewQualityPreset? preset,
    Duration? startPosition,
    ExportSettings? settings,
    Function(ExportProgress progress)? onProgress,
  }) async {
    if (timeline.tracks.isEmpty || timeline.duration == Duration.zero) {
      throw Exception('Timeline is empty');
    }

    _log(
      'loadTimelinePreview start',
      error: {
        'durationMs': timeline.duration.inMilliseconds,
        'tracks': timeline.tracks.length,
        'clips': timeline.tracks.fold<int>(0, (sum, t) => sum + t.clips.length),
      },
    );

    final effectivePreset = preset ?? state.timelinePreviewPreset;
    final start = startPosition ?? timeline.currentPosition;
    final cacheKey = _hlsCacheKey(
      timeline: timeline,
      preset: effectivePreset,
      startPosition: start,
    );

    state = state.copyWith(
      isLoading: true,
      error: null,
      timelinePreviewPreset: effectivePreset,
      isTimelineStreaming: true,
    );

    // If we already have a cached stream for this exact request, reuse it.
    final cached = _hlsCache[cacheKey];
    if (cached != null && await File(cached.playlistPath).exists()) {
      _ensurePlayerInitialized();
      _hlsSession = cached;
      _lastStreamTimeline = timeline;
      _lastStreamMediaLibrary = List<MediaItem>.from(mediaLibrary);

      final player = _player!;
      await player.open(Media(cached.playlistPath), play: false);
      await player.setRate(state.speed.value);

      state = state.copyWith(
        isLoading: false,
        timelinePreviewPath: cached.playlistPath,
        currentVideoPath: cached.playlistPath,
        playbackVideoPath: cached.playlistPath,
        isTimelineStreaming: true,
        timelineStreamStartOffset: cached.startOffset,
        isEffectPreview: false,
        effectPreviewPath: null,
      );
      return;
    }

    await _detachTimelineStream();
    await pause();
    _ensurePlayerInitialized();

    _lastStreamTimeline = timeline;
    _lastStreamMediaLibrary = List<MediaItem>.from(mediaLibrary);

    final streamSettings =
        settings ?? _settingsForTimelineStream(preset: effectivePreset);

    final startedAt = DateTime.now();
    onProgress?.call(
      const ExportProgress(progress: 0.0, elapsed: Duration.zero),
    );

    try {
      _log(
        'loadTimelinePreview startTimelineHlsPreview start',
        error: {
          'startMs': start.inMilliseconds,
          'preset': effectivePreset.name,
        },
      );
      final session = await _exportEngine.startTimelineHlsPreview(
        timeline,
        mediaLibrary,
        streamSettings,
        startPosition: start,
      );
      _hlsSession = session;
      _hlsCache[cacheKey] = session;
      while (_hlsCache.length > _maxCachedHlsStreams) {
        final oldestKey = _hlsCache.keys.first;
        final toEvict = _hlsCache.remove(oldestKey);
        if (toEvict != null) {
          try {
            await toEvict.stop();
          } catch (_) {}
        }
      }

      // Wait for playlist to appear and include at least one segment.
      //
      // Some effects (e.g. heavy denoise) can delay the first segment.
      // Don't throw at 5s; keep waiting up to 60s.
      final readyFast = await _waitForHlsReady(
        session.playlistPath,
        timeout: const Duration(seconds: 5),
        onTick: (elapsed) {
          final p = (elapsed.inMilliseconds / 5000.0).clamp(0.0, 0.9);
          onProgress?.call(
            ExportProgress(
              progress: p,
              elapsed: DateTime.now().difference(startedAt),
            ),
          );
        },
      );
      if (!readyFast) {
        final readySlow = await _waitForHlsReady(
          session.playlistPath,
          timeout: const Duration(seconds: 55),
          onTick: (elapsed) {
            // Continue to show progress without hitting 100% until ready.
            final p = (0.9 + (elapsed.inMilliseconds / 55000.0) * 0.09).clamp(
              0.9,
              0.99,
            );
            onProgress?.call(
              ExportProgress(
                progress: p,
                elapsed: DateTime.now().difference(startedAt),
              ),
            );
          },
        );
        if (!readySlow) {
          throw Exception('HLS playlist not ready within 60s');
        }
      }

      final player = _player!;
      await player.open(Media(session.playlistPath), play: false);
      await player.setRate(state.speed.value);

      state = state.copyWith(
        isLoading: false,
        timelinePreviewPath: session.playlistPath,
        currentVideoPath: session.playlistPath,
        playbackVideoPath: session.playlistPath,
        isTimelineStreaming: true,
        timelineStreamStartOffset: session.startOffset,
        isEffectPreview: false,
        effectPreviewPath: null,
      );

      onProgress?.call(
        ExportProgress(
          progress: 1.0,
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    } catch (e) {
      _log('loadTimelinePreview startTimelineHlsPreview failed', error: e);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to start timeline stream preview: $e',
        isTimelineStreaming: false,
        timelineStreamStartOffset: Duration.zero,
      );
      rethrow;
    }
  }

  /// Invalidate timeline preview when timeline is modified
  void invalidateTimelinePreview() {
    unawaited(clearTimelinePreviewCache());

    // Clear the timeline preview path so it will be regenerated on next play
    state = state.copyWith(
      timelinePreviewPath: null,
      currentVideoPath: null,
      playbackVideoPath: null,
      isTimelineStreaming: false,
      timelineStreamStartOffset: Duration.zero,
    );
  }

  @override
  void dispose() {
    // Best-effort cleanup.
    _cleanupEffectPreviewTemps();
    _cleanupPreviewProxyTemps();
    unawaited(clearTimelinePreviewCache());
    _seekDebounce?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<String> _createTempOutputPath({String suffix = 'preview'}) async {
    final dir = Directory.systemTemp;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/${suffix}_$timestamp.mp4';
  }
}

/// Preview provider
final previewProvider = StateNotifierProvider<PreviewNotifier, PreviewState>((
  ref,
) {
  return PreviewNotifier();
});
