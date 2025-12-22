import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';
import 'package:video_editor/core/engines/export_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/models/enums.dart' as enums;
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
  final VideoPlayerController? controller;
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
  final String? timelinePreviewPath;
  final enums.PreviewQualityPreset timelinePreviewPreset;

  const PreviewState({
    this.controller,
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
    this.timelinePreviewPath,
    this.timelinePreviewPreset = enums.PreviewQualityPreset.quick,
  });

  static const Object _unset = Object();

  PreviewState copyWith({
    Object? controller = _unset,
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
    Object? timelinePreviewPath = _unset,
    enums.PreviewQualityPreset? timelinePreviewPreset,
  }) {
    return PreviewState(
      controller:
          identical(controller, _unset) ? this.controller : controller as VideoPlayerController?,
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
      timelinePreviewPath: identical(timelinePreviewPath, _unset)
          ? this.timelinePreviewPath
          : timelinePreviewPath as String?,
      timelinePreviewPreset: timelinePreviewPreset ?? this.timelinePreviewPreset,
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
  final Map<enums.PreviewQualityPreset, String> _timelinePreviewPaths = {};

  static String get _previewLogPath =>
      '${Directory.systemTemp.path}/video_editor_preview.log';

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    try {
      final now = DateTime.now().toIso8601String();
      final buffer = StringBuffer('[$now] $message\n');
      if (error != null) buffer.write('error: $error\n');
      if (stackTrace != null) buffer.write('$stackTrace\n');
      buffer.write('\n');
      File(_previewLogPath)
          .writeAsStringSync(buffer.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> _disposeController(VideoPlayerController? controller) async {
    if (controller == null) return;
    controller.removeListener(_onPlayerUpdate);
    await controller.dispose();
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

  Future<void> _cleanupTimelinePreviewTemps() async {
    final paths = List<String>.from(_timelinePreviewPaths.values);
    _timelinePreviewPaths.clear();
    for (final p in paths) {
      try {
        final file = File(p);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
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
    final isHdr = transfer == 'arib-std-b67' ||
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

    _log('Generating preview proxy', error: {
      'input': filePath,
      'output': proxyPath,
      'stream': stream,
    });

    // Try to use hardware encoder for faster proxy generation
    final hardwareEncoder = await _detectHardwareEncoder();
    final useHardware = hardwareEncoder != null;

    final args = [
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

    final result = await Process.run('ffmpeg', args);

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
      final result = await Process.run('ffmpeg', [
        '-hide_banner',
        '-encoders',
      ]);

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
    // Clear any previous playback state immediately to avoid interacting with a disposed controller.
    final previousController = state.controller;

    state = state.copyWith(
      controller: null,
      isPlaying: false,
      currentPosition: Duration.zero,
      duration: Duration.zero,
      isLoading: true,
      error: null,
      isEffectPreview: false,
      effectPreviewPath: null,
      timelinePreviewPath: null,
      currentVideoPath: null,
      playbackVideoPath: null,
    );

    try {
      // Dispose previous controller (after clearing state).
      await _disposeController(previousController);
      await _cleanupEffectPreviewTemps();
      await _cleanupPreviewProxyTemps();

      final playbackPath = await _ensurePreviewPlayable(filePath);

      // Create new controller
      final file = File(playbackPath);
      final controller = VideoPlayerController.file(file);

      // Initialize controller
      await controller.initialize();

      // Set playback speed
      await controller.setPlaybackSpeed(state.speed.value);

      // Update state
      state = state.copyWith(
        controller: controller,
        isLoading: false,
        duration: controller.value.duration,
        currentVideoPath: filePath,
        playbackVideoPath: playbackPath,
        isEffectPreview: false,
        effectPreviewPath: null,
        timelinePreviewPath: null,
        error: null,
      );

      // Listen to position updates
      controller.addListener(_onPlayerUpdate);
    } catch (e) {
      _log('loadVideo failed', error: e);
      state = state.copyWith(
        controller: null,
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
    final controller = state.controller;
    if (controller != null &&
        controller.value.isInitialized &&
        !state.isPlaying) {
      try {
        _log('play()');
        await state.controller!.play();
        state = state.copyWith(isPlaying: true);
      } catch (e, st) {
        _log('play() failed', error: e, stackTrace: st);
        state = state.copyWith(error: 'Failed to play: $e');
      }
    }
  }

  /// Pause the video
  Future<void> pause() async {
    final controller = state.controller;
    if (controller != null &&
        controller.value.isInitialized &&
        state.isPlaying) {
      try {
        _log('pause()');
        await state.controller!.pause();
        state = state.copyWith(isPlaying: false);
      } catch (e, st) {
        _log('pause() failed', error: e, stackTrace: st);
        state = state.copyWith(error: 'Failed to pause: $e');
      }
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
    final controller = state.controller;
    if (controller != null && controller.value.isInitialized) {
      await state.controller!.seekTo(position);
      state = state.copyWith(currentPosition: position);
    }
  }

  /// Set playback speed
  Future<void> setPlaybackSpeed(PlaybackSpeed speed) async {
    state = state.copyWith(speed: speed);
    final controller = state.controller;
    if (controller != null && controller.value.isInitialized) {
      await controller.setPlaybackSpeed(speed.value);
    }
  }

  /// Unload current video
  Future<void> unloadVideo() async {
    final controller = state.controller;

    state = state.copyWith(
      controller: null,
      isPlaying: false,
      isLoading: false,
      currentPosition: Duration.zero,
      duration: Duration.zero,
      currentVideoPath: null,
      playbackVideoPath: null,
      error: null,
      isEffectPreview: false,
      effectPreviewPath: null,
      timelinePreviewPath: null,
      speed: state.speed,
    );

    await _disposeController(controller);
    await _cleanupEffectPreviewTemps();
    await _cleanupPreviewProxyTemps();
    await _cleanupTimelinePreviewTemps();
  }

  Future<void> setTimelinePreviewPreset(enums.PreviewQualityPreset preset) async {
    if (preset == state.timelinePreviewPreset) return;

    // If currently playing a timeline preview, stop playback to avoid desync.
    if (state.isPlaying &&
        state.timelinePreviewPath != null &&
        state.currentVideoPath == state.timelinePreviewPath) {
      await pause();
    }

    final cachedPath = _timelinePreviewPaths[preset];
    if (cachedPath == null) {
      state = state.copyWith(
        timelinePreviewPreset: preset,
        timelinePreviewPath: null,
      );
      return;
    }

    final exists = await File(cachedPath).exists();
    state = state.copyWith(
      timelinePreviewPreset: preset,
      timelinePreviewPath: exists ? cachedPath : null,
    );
  }

  ExportSettings _settingsForTimelinePreview({
    required enums.PreviewQualityPreset preset,
    required String outputPath,
  }) {
    switch (preset) {
      case enums.PreviewQualityPreset.draft:
        return ExportSettings(
          outputPath: outputPath,
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r480p,
          quality: enums.Quality.low,
          frameRate: 12,
          videoPreset: 'ultrafast',
          audioSettings: const AudioSettings(bitrate: 96000),
        );
      case enums.PreviewQualityPreset.quick:
        return ExportSettings(
          outputPath: outputPath,
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r480p,
          quality: enums.Quality.low,
          frameRate: 15,
          videoPreset: 'ultrafast',
          audioSettings: const AudioSettings(bitrate: 96000),
        );
      case enums.PreviewQualityPreset.balanced:
        return ExportSettings(
          outputPath: outputPath,
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r720p,
          quality: enums.Quality.standard,
          frameRate: 24,
          videoPreset: 'veryfast',
          audioSettings: const AudioSettings(bitrate: 128000),
        );
      case enums.PreviewQualityPreset.standard:
        return ExportSettings(
          outputPath: outputPath,
          format: enums.VideoFormat.mp4,
          resolution: enums.Resolution.r720p,
          quality: enums.Quality.standard,
          frameRate: 30,
          videoPreset: 'medium',
          audioSettings: const AudioSettings(bitrate: 192000),
        );
    }
  }

  /// Generate effect preview
  /// NOTE: Full FFmpeg integration requires additional setup
  /// This is a placeholder that marks the preview state
  Future<void> generateEffectPreview(List<Effect> effects) async {
    if (state.currentVideoPath == null || effects.isEmpty) {
      return;
    }

    try {
      state = state.copyWith(isLoading: true, error: null);

      final previousController = state.controller;
      state = state.copyWith(controller: null);
      await _disposeController(previousController);
      await _cleanupEffectPreviewTemps();

      var inputPath = state.currentVideoPath!;

      for (final effect in effects) {
        final tempFile = await _createTempOutputPath();
        _effectPreviewTempPaths.add(tempFile);
        await _videoEngine.applyEffect(inputPath, tempFile, effect);
        inputPath = tempFile;
      }

      final controller = VideoPlayerController.file(File(inputPath));
      await controller.initialize();
      await controller.setPlaybackSpeed(state.speed.value);
      controller.addListener(_onPlayerUpdate);

      state = state.copyWith(
        controller: controller,
        isLoading: false,
        duration: controller.value.duration,
        isEffectPreview: true,
        effectPreviewPath: inputPath,
        error: null,
      );
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

    final originalPath = state.currentVideoPath;

    await _cleanupEffectPreviewTemps();

    if (originalPath != null) {
      await loadVideo(originalPath);
    } else {
      state = state.copyWith(
        isEffectPreview: false,
        effectPreviewPath: null,
      );
    }
  }

  Future<void> loadTimelinePreview(
    Timeline timeline,
    List<MediaItem> mediaLibrary, {
    enums.PreviewQualityPreset? preset,
    ExportSettings? settings,
    Function(ExportProgress progress)? onProgress,
  }) async {
    if (timeline.tracks.isEmpty || timeline.duration == Duration.zero) {
      throw Exception('Timeline is empty');
    }

    _log('loadTimelinePreview start', error: {
      'durationMs': timeline.duration.inMilliseconds,
      'tracks': timeline.tracks.length,
      'clips': timeline.tracks.fold<int>(0, (sum, t) => sum + t.clips.length),
    });

    final effectivePreset = preset ?? state.timelinePreviewPreset;

    state = state.copyWith(
      isLoading: true,
      error: null,
      timelinePreviewPreset: effectivePreset,
    );

    final cachedPath = _timelinePreviewPaths[effectivePreset];
    if (cachedPath != null && await File(cachedPath).exists()) {
      await loadVideo(cachedPath);
      state = state.copyWith(timelinePreviewPath: cachedPath);
      return;
    }

    final previewPath = await _createTempOutputPath(suffix: 'timeline');
    _log('loadTimelinePreview output path', error: previewPath);

    final existingPathForPreset = _timelinePreviewPaths[effectivePreset];
    if (existingPathForPreset != null) {
      try {
        final file = File(existingPathForPreset);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _timelinePreviewPaths.remove(effectivePreset);
    }

    final exportSettings = settings ??
        _settingsForTimelinePreview(preset: effectivePreset, outputPath: previewPath);

    try {
      _log('loadTimelinePreview exportTimeline start');
      await _exportEngine.exportTimeline(
        timeline,
        mediaLibrary,
        exportSettings,
        onProgress ?? (_) {},
      );
      _log('loadTimelinePreview exportTimeline done');
    } catch (e) {
      _log('loadTimelinePreview exportTimeline failed', error: e);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to render timeline preview: $e',
      );
      rethrow;
    }

    try {
      _log('loadTimelinePreview loadVideo start', error: previewPath);
      await loadVideo(previewPath);
      _log('loadTimelinePreview loadVideo done');
      _timelinePreviewPaths[effectivePreset] = previewPath;
      state = state.copyWith(timelinePreviewPath: previewPath);
    } catch (e) {
      _log('loadTimelinePreview loadVideo failed', error: e);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load rendered preview: $e',
      );
      rethrow;
    }
  }

  /// Invalidate timeline preview when timeline is modified
  void invalidateTimelinePreview() {
    if (_timelinePreviewPaths.isEmpty && state.timelinePreviewPath == null) {
      return;
    }

    // Best-effort cleanup (async, don't block UI).
    _cleanupTimelinePreviewTemps();

    // Clear the timeline preview path so it will be regenerated on next play
    state = state.copyWith(
      timelinePreviewPath: null,
      currentVideoPath: null,
    );
  }

  /// Called when player state changes
  void _onPlayerUpdate() {
    if (state.controller != null) {
      final controller = state.controller!;
      state = state.copyWith(
        currentPosition: controller.value.position,
        isPlaying: controller.value.isPlaying,
      );

      // Auto-pause when video ends
      if (controller.value.position >= controller.value.duration) {
        pause();
      }
    }
  }

  @override
  void dispose() {
    // Best-effort cleanup.
    _cleanupEffectPreviewTemps();
    _cleanupPreviewProxyTemps();
    _cleanupTimelinePreviewTemps();
    state.controller?.removeListener(_onPlayerUpdate);
    state.controller?.dispose();
    super.dispose();
  }

  Future<String> _createTempOutputPath({String suffix = 'preview'}) async {
    final dir = Directory.systemTemp;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/${suffix}_$timestamp.mp4';
  }
}

/// Preview provider
final previewProvider =
    StateNotifierProvider<PreviewNotifier, PreviewState>((ref) {
  return PreviewNotifier();
});
