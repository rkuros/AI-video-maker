import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/platform/coreml_denoise.dart';

/// Engine for exporting timeline to video file using system FFmpeg.
class ExportEngine {
  static const _ffmpeg = 'ffmpeg';
  static const _ffprobe = 'ffprobe';

  // Cache for available hardware encoders
  String? _cachedHardwareEncoder;
  bool _hardwareEncoderChecked = false;

  // Current export process for cancellation
  Process? _currentProcess;
  bool _cancelRequested = false;

  /// Cancel the current export operation
  void cancelExport() {
    _cancelRequested = true;
    _currentProcess?.kill();
  }

  /// Start a low-latency HLS preview stream for the timeline from [startPosition].
  ///
  /// The generated playlist file can be opened while FFmpeg is still writing.
  Future<HlsPreviewSession> startTimelineHlsPreview(
    Timeline timeline,
    List<MediaItem> mediaLibrary,
    ExportSettings settings, {
    required Duration startPosition,
    Duration? maxDuration,
  }) async {
    if (timeline.tracks.isEmpty) {
      throw Exception('Timeline is empty');
    }

    if (timeline.videoTracks.isEmpty) {
      throw Exception('No video tracks found');
    }

    await _assertFfmpegAvailable();

    final timelineDuration = timeline.duration;
    if (timelineDuration == Duration.zero) {
      throw Exception('Timeline has zero duration');
    }

    var start = startPosition;
    if (start < Duration.zero) start = Duration.zero;
    if (start >= timelineDuration) {
      start = timelineDuration - const Duration(milliseconds: 1);
    }

    final remaining = timelineDuration - start;
    final requested = maxDuration != null && maxDuration > Duration.zero
        ? (maxDuration < remaining ? maxDuration : remaining)
        : remaining;

    final width = settings.resolution.width;
    final height = settings.resolution.height;
    final fps = settings.frameRate;
    final crf = _getQualityCRF(settings.quality);
    final audio = settings.audioSettings;

    // Prefer GPU encoding when available (e.g., VideoToolbox on macOS).
    final hardwareEncoder = await _detectHardwareEncoder();
    final useHardware = hardwareEncoder != null;

    final mediaMap = {for (final item in mediaLibrary) item.id: item};

    // Build a ranged timeline (shifted so that [start] becomes 0:00).
    final rangedTracks = <Track>[];
    for (final track in timeline.tracks) {
      final rangedClips = <Clip>[];
      for (final clip in track.clips) {
        final clipDuration = _clipDuration(clip);
        if (clipDuration <= Duration.zero) continue;

        final clipStart = clip.startTime;
        final clipEnd = clipStart + clipDuration;
        final rangeStart = start;
        final rangeEnd = start + requested;

        final segStart = clipStart > rangeStart ? clipStart : rangeStart;
        final segEnd = clipEnd < rangeEnd ? clipEnd : rangeEnd;
        final segDuration = segEnd - segStart;
        if (segDuration <= Duration.zero) continue;

        final mediaItem = mediaMap[clip.mediaItemId];
        if (mediaItem == null) {
          throw Exception('Missing media for clip: ${clip.mediaItemId}');
        }

        final sourceOffset = segStart - clipStart;
        final rangedSourceStart = clip.sourceStart + sourceOffset;
        final rangedStart = segStart - start;
        final rangedEnd = rangedStart + segDuration;

        rangedClips.add(
          clip.copyWith(
            startTime: rangedStart,
            endTime: rangedEnd,
            sourceStart: rangedSourceStart,
            sourceDuration: segDuration,
          ),
        );
      }
      if (rangedClips.isNotEmpty) {
        rangedTracks.add(track.copyWith(clips: rangedClips));
      }
    }

    final rangedTimeline = timeline.copyWith(tracks: rangedTracks);
    if (rangedTimeline.videoTracks.isEmpty) {
      throw Exception('No clips to preview at the selected position');
    }

    // Collect inputs for ranged timeline (must preserve input index order).
    final inputs = <_InputSpec>[];
    var inputIndex = 0;
    for (final track in rangedTimeline.tracks) {
      for (final clip in track.clips) {
        final item = mediaMap[clip.mediaItemId];
        if (item == null) {
          throw Exception('Missing media for clip: ${clip.mediaItemId}');
        }
        inputs.add(
          _InputSpec(
            inputIndex: inputIndex,
            mediaItem: item,
            clip: clip,
            track: track,
          ),
        );
        inputIndex += 1;
      }
    }

    // Probe audio stream existence asynchronously to avoid blocking the UI isolate.
    final audioAvailability = <String, bool>{};
    final toProbe = inputs
        .map((s) => s.mediaItem.filePath)
        .where((p) => audioAvailability[p] == null)
        .toSet()
        .toList();
    await Future.wait(
      toProbe.map((p) async {
        audioAvailability[p] = await _hasAudioStreamAsync(p);
      }),
    );

    final inputArgs = <String>[];
    for (final spec in inputs) {
      if (spec.mediaItem.type == MediaType.image) {
        inputArgs.addAll([
          '-loop',
          '1',
          '-t',
          _seconds(spec.clipDuration),
        ]);
      }
      inputArgs.addAll(['-i', spec.mediaItem.filePath]);
    }

    final graph = _buildFilterGraph(
      inputs: inputs,
      timeline: rangedTimeline,
      duration: requested,
      width: width,
      height: height,
      fps: fps,
      audioAvailability: audioAvailability,
      fastPreview: false,
    );

    final sessionDir = await Directory.systemTemp.createTemp('video_editor_hls_');
    final playlistPath = path.join(sessionDir.path, 'stream.m3u8');
    final segmentPattern = path.join(sessionDir.path, 'seg_%05d.m4s');

    final args = <String>[
      '-y',
      if (useHardware) ...[
        '-hwaccel',
        'auto',
      ],
      ...inputArgs,
      '-filter_complex',
      graph,
      '-map',
      '[vout]',
      '-map',
      '[aout]',
      '-r',
      fps.toString(),
      '-c:v',
      useHardware ? hardwareEncoder : 'libx264',
    ];

    if (useHardware) {
      final bitrate = _getQualityBitrate(settings.quality, width, height);
      args.addAll([
        '-b:v',
        bitrate,
        '-maxrate',
        bitrate,
      ]);
      if (hardwareEncoder == 'h264_videotoolbox') {
        args.addAll([
          '-allow_sw',
          '1',
        ]);
      }
    } else {
      args.addAll([
        '-crf',
        crf.toString(),
        '-preset',
        settings.videoPreset,
        '-tune',
        'zerolatency',
      ]);
    }

    args.addAll([
      '-pix_fmt',
      'yuv420p',
      '-g',
      max(1, fps * 2).toString(),
      '-keyint_min',
      max(1, fps).toString(),
      '-sc_threshold',
      '0',
      '-c:a',
      audio.codec,
      '-b:a',
      _bitrateArg(audio.bitrate),
      '-ar',
      audio.sampleRate.toString(),
      '-ac',
      audio.channels.toString(),
      '-muxdelay',
      '0',
      '-muxpreload',
      '0',
      '-f',
      'hls',
      '-hls_time',
      '0.5',
      '-hls_list_size',
      '8',
      '-hls_flags',
      'delete_segments+append_list+independent_segments',
      '-hls_segment_type',
      'fmp4',
      '-hls_fmp4_init_filename',
      'init.mp4',
      '-hls_segment_filename',
      segmentPattern,
      playlistPath,
    ]);

    final process = await Process.start(
      _ffmpeg,
      args,
      mode: ProcessStartMode.detachedWithStdio,
    );

    return HlsPreviewSession._(
      directory: sessionDir,
      playlistPath: playlistPath,
      startOffset: start,
      duration: requested,
      process: process,
    );
  }

  /// Export timeline to video file.
  Future<void> exportTimeline(
    Timeline timeline,
    List<MediaItem> mediaLibrary,
    ExportSettings settings,
    Function(ExportProgress progress) onProgress,
  ) async {
    if (timeline.tracks.isEmpty) {
      throw Exception('Timeline is empty');
    }

    if (timeline.videoTracks.isEmpty) {
      throw Exception('No video tracks found');
    }

    await _assertFfmpegAvailable();

    final duration = timeline.duration;
    if (duration == Duration.zero) {
      throw Exception('Timeline has zero duration');
    }

    final prepared = await _prepareTimelineForCoreMlDenoise(timeline, mediaLibrary);
    final effectiveTimeline = prepared.$1;
    final effectiveLibrary = prepared.$2;
    final cleanupDirs = prepared.$3;

    try {
      final outputDir = Directory(path.dirname(settings.outputPath));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final width = settings.resolution.width;
      final height = settings.resolution.height;
      final fps = settings.frameRate;
      final crf = _getQualityCRF(settings.quality);
      final audio = settings.audioSettings;

      final mediaMap = {for (final item in effectiveLibrary) item.id: item};
      final inputs = <_InputSpec>[];
      var inputIndex = 0;

      for (final track in effectiveTimeline.tracks) {
        for (final clip in track.clips) {
          final item = mediaMap[clip.mediaItemId];
          if (item == null) {
            throw Exception('Missing media for clip: ${clip.mediaItemId}');
          }
          final clipDuration = _clipDuration(clip);
          if (clipDuration <= Duration.zero) {
            continue;
          }
          inputs.add(
            _InputSpec(
              inputIndex: inputIndex,
              mediaItem: item,
              clip: clip,
              track: track,
            ),
          );
          inputIndex += 1;
        }
      }

      if (inputs.isEmpty) {
        throw Exception('No clips to export');
      }

      // Probe audio stream existence asynchronously to avoid blocking the UI isolate.
      final audioAvailability = <String, bool>{};
      final toProbe = inputs
          .map((s) => s.mediaItem.filePath)
          .where((p) => audioAvailability[p] == null)
          .toSet()
          .toList();
      await Future.wait(
        toProbe.map((p) async {
          audioAvailability[p] = await _hasAudioStreamAsync(p);
        }),
      );

      final inputArgs = <String>[];
      for (final spec in inputs) {
        if (spec.mediaItem.type == MediaType.image) {
          inputArgs.addAll([
            '-loop',
            '1',
            '-t',
            _seconds(spec.clipDuration),
          ]);
        }
        inputArgs.addAll(['-i', spec.mediaItem.filePath]);
      }

      final graph = _buildFilterGraph(
        inputs: inputs,
        timeline: effectiveTimeline,
        duration: duration,
        width: width,
        height: height,
        fps: fps,
        audioAvailability: audioAvailability,
      );

      // Detect hardware encoder
      final hardwareEncoder = await _detectHardwareEncoder();
      final useHardware = hardwareEncoder != null;

      final args = <String>[
        '-y',
        ...inputArgs,
        '-filter_complex',
        graph,
        '-map',
        '[vout]',
        '-map',
        '[aout]',
        '-r',
        fps.toString(),
        '-c:v',
        useHardware ? hardwareEncoder : 'libx264',
      ];

      // Add quality settings based on encoder type
      if (useHardware) {
        // Hardware encoders typically use bitrate-based encoding
        final bitrate = _getQualityBitrate(settings.quality, width, height);
        args.addAll([
          '-b:v',
          bitrate,
        ]);

        // VideoToolbox works best with minimal extra settings
        // Let it auto-detect the best profile and level based on input
      } else {
        // Software encoder uses CRF
        args.addAll([
          '-crf',
          crf.toString(),
          '-preset',
          settings.videoPreset,
        ]);
      }

      args.addAll([
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        audio.codec,
        '-b:a',
        _bitrateArg(audio.bitrate),
        '-ar',
        audio.sampleRate.toString(),
        '-ac',
        audio.channels.toString(),
        '-movflags',
        '+faststart',
        '-progress',
        'pipe:1',
        '-nostats',
        settings.outputPath,
      ]);

      await _runWithProgress(
        args,
        duration,
        onProgress,
      );
    } finally {
      for (final dir in cleanupDirs) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<(Timeline, List<MediaItem>, List<Directory>)> _prepareTimelineForCoreMlDenoise(
    Timeline timeline,
    List<MediaItem> mediaLibrary,
  ) async {
    if (!Platform.isMacOS) return (timeline, mediaLibrary, const <Directory>[]);

    final mediaMap = {for (final item in mediaLibrary) item.id: item};

    var needsCoreMl = false;
    for (final track in timeline.tracks) {
      for (final clip in track.clips) {
        for (final effect in clip.effects) {
          if (effect.type != 'auto_denoise' && effect.type != 'low_light_denoise') {
            continue;
          }
          final s = DenoiseSettings.fromJson(effect.parameters);
          final wantsCoreMl = s.backend == DenoiseBackend.coreML || s.useAiModel;
          if (wantsCoreMl && (s.aiModelPath?.isNotEmpty ?? false)) {
            needsCoreMl = true;
            break;
          }
        }
        if (needsCoreMl) break;
      }
      if (needsCoreMl) break;
    }
    if (!needsCoreMl) {
      return (timeline, mediaLibrary, const <Directory>[]);
    }

    final tempDir = await Directory.systemTemp.createTemp('video_editor_coreml_');

    final proxyCache = <String, MediaItem>{};
    final updatedMedia = [...mediaLibrary];
    final updatedTracks = <Track>[];

    for (final track in timeline.tracks) {
      final updatedClips = <Clip>[];
      for (final clip in track.clips) {
        final item = mediaMap[clip.mediaItemId];
        if (item == null) {
          updatedClips.add(clip);
          continue;
        }

        DenoiseSettings? denoiseSettings;
        for (final effect in clip.effects) {
          if (effect.type != 'auto_denoise' && effect.type != 'low_light_denoise') {
            continue;
          }
          final s = DenoiseSettings.fromJson(effect.parameters);
          final wantsCoreMl = s.backend == DenoiseBackend.coreML || s.useAiModel;
          if (wantsCoreMl && (s.aiModelPath?.isNotEmpty ?? false)) {
            denoiseSettings = s;
            break;
          }
        }

        if (denoiseSettings == null) {
          updatedClips.add(clip);
          continue;
        }

        final modelPath = denoiseSettings.aiModelPath!;
        final modelExists = File(modelPath).existsSync() || Directory(modelPath).existsSync();
        if (!modelExists) {
          updatedClips.add(clip);
          continue;
        }

        final key = '${item.filePath}|${clip.sourceStart.inMilliseconds}|'
            '${clip.sourceDuration.inMilliseconds}|$modelPath';

        final proxy = proxyCache[key] ??
            MediaItem(
              name: '${item.name} (CoreML denoise)',
              filePath: path.join(tempDir.path, '${clip.id}.mp4'),
              type: MediaType.video,
              duration: clip.sourceDuration,
            );

        if (proxyCache[key] == null) {
          await CoreMlDenoise.denoiseVideo(
            inputPath: item.filePath,
            outputPath: proxy.filePath,
            sourceStart: clip.sourceStart,
            duration: clip.sourceDuration,
            modelPath: modelPath,
          );
          proxyCache[key] = proxy;
          updatedMedia.add(proxy);
        }

        final remainingEffects = clip.effects
            .where((e) => e.type != 'auto_denoise' && e.type != 'low_light_denoise')
            .toList();

        updatedClips.add(
          clip.copyWith(
            mediaItemId: proxy.id,
            sourceStart: Duration.zero,
            sourceDuration: clip.sourceDuration,
            effects: remainingEffects,
          ),
        );
      }
      updatedTracks.add(track.copyWith(clips: updatedClips));
    }

    return (timeline.copyWith(tracks: updatedTracks), updatedMedia, [tempDir]);
  }

  Future<void> _assertFfmpegAvailable() async {
    final ffmpegResult = await Process.run(_ffmpeg, ['-version']);
    if (ffmpegResult.exitCode != 0) {
      throw Exception('FFmpeg not found. Please install FFmpeg.');
    }
    final ffprobeResult = await Process.run(_ffprobe, ['-version']);
    if (ffprobeResult.exitCode != 0) {
      throw Exception('ffprobe not found. Please install FFmpeg.');
    }
  }

  /// Detect and return the best available hardware encoder.
  /// Returns null if no hardware encoder is available.
  Future<String?> _detectHardwareEncoder() async {
    if (_hardwareEncoderChecked) {
      return _cachedHardwareEncoder;
    }

    _hardwareEncoderChecked = true;

    try {
      // Get list of all available encoders once
      final result = await Process.run(_ffmpeg, [
        '-hide_banner',
        '-encoders',
      ]);

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout as String;

      // List of hardware encoders to try, in order of preference
      final encodersToTry = [
        'h264_videotoolbox', // macOS VideoToolbox
        'h264_nvenc',        // NVIDIA GPU
        'h264_qsv',          // Intel Quick Sync Video
        'h264_vaapi',        // Linux VA-API
      ];

      // Check which encoders are available, return the first one found
      for (final encoder in encodersToTry) {
        if (output.contains(encoder)) {
          _cachedHardwareEncoder = encoder;
          return encoder;
        }
      }
    } catch (_) {
      // Hardware encoder detection failed, fall back to software
    }

    return null;
  }

  String _buildFilterGraph({
    required List<_InputSpec> inputs,
    required Timeline timeline,
    required Duration duration,
    required int width,
    required int height,
    required int fps,
    required Map<String, bool> audioAvailability,
    bool fastPreview = false,
  }) {
    final filters = <String>[];
    final timelineSeconds = duration.inMilliseconds / 1000.0;
    var currentVideoLabel = 'vbase0';
    var currentAudioLabel = 'abase0';

    filters.add(
      'color=c=black:s=${width}x$height:d=${timelineSeconds.toStringAsFixed(3)}'
      ',fps=$fps,format=rgba,setsar=1'
      '[$currentVideoLabel]',
    );
    filters.add(
      'anullsrc=channel_layout=stereo:sample_rate=44100:'
      'd=${timelineSeconds.toStringAsFixed(3)}[$currentAudioLabel]',
    );

    final videoTracks = timeline.videoTracks;
    for (var trackIndex = 0; trackIndex < videoTracks.length; trackIndex++) {
      final track = videoTracks[trackIndex];
      final trackInputs = inputs
          .where((spec) => spec.track.id == track.id)
          .where((spec) =>
              spec.mediaItem.type == MediaType.video ||
              spec.mediaItem.type == MediaType.image)
          .toList()
        ..sort((a, b) => a.clip.startTime.compareTo(b.clip.startTime));

      if (trackInputs.isEmpty) continue;

      final trackLabel = _buildVideoTrackStream(
        filters: filters,
        trackInputs: trackInputs,
        timelineDuration: duration,
        width: width,
        height: height,
        trackIndex: trackIndex,
        fps: fps,
        fastPreview: fastPreview,
      );

      final nextVideoLabel = 'vbase_track$trackIndex';
      filters.add(
        '[$currentVideoLabel][$trackLabel]overlay=eof_action=pass[$nextVideoLabel]',
      );
      currentVideoLabel = nextVideoLabel;
    }

    for (final spec in inputs) {
      final item = spec.mediaItem;
      final clip = spec.clip;
      final track = spec.track;

      final hasAudio = item.type == MediaType.audio || item.type == MediaType.video;
      if (!hasAudio || _isMuted(track, clip)) {
        continue;
      }
      if (audioAvailability[item.filePath] != true) {
        continue;
      }

      final clipDuration = spec.clipDuration;
      final clipStart = clip.startTime;

      final volume = _effectiveVolume(track, clip);
      final audioFilters = <String>[
        'atrim=start=${_seconds(clip.sourceStart)}:duration=${_seconds(clipDuration)}',
        'asetpts=PTS-STARTPTS',
      ];
      if (volume != 1.0) {
        audioFilters.add('volume=${volume.toStringAsFixed(3)}');
      }
      audioFilters.addAll(_buildAudioTransitionFilters(clip, clipDuration));

      final audioLabel = 'aclip${spec.inputIndex}';
      filters.add(
        '[${spec.inputIndex}:a]${audioFilters.join(',')}[$audioLabel]',
      );

      final delayMs = clipStart.inMilliseconds;
      final delayedLabel = 'adelay${spec.inputIndex}';
      filters.add(
        '[$audioLabel]adelay=$delayMs|$delayMs[$delayedLabel]',
      );

      final nextAudioLabel = 'abase${spec.inputIndex + 1}';
      filters.add(
        '[$currentAudioLabel][$delayedLabel]'
        'amix=inputs=2:duration=longest:dropout_transition=0'
        '[$nextAudioLabel]',
      );
      currentAudioLabel = nextAudioLabel;
    }

    filters.add('[$currentVideoLabel]format=yuv420p[vout]');
    filters.add('[$currentAudioLabel]anull[aout]');

    return filters.join(';');
  }

	  String _buildVideoTrackStream({
	    required List<String> filters,
	    required List<_InputSpec> trackInputs,
	    required Duration timelineDuration,
	    required int width,
	    required int height,
	    required int trackIndex,
	    required int fps,
      required bool fastPreview,
	  }) {
	    String? currentLabel;
	    var currentDuration = Duration.zero;
	    Clip? previousClip;
	    var previousClipDuration = Duration.zero;

	    for (var i = 0; i < trackInputs.length; i++) {
	      final spec = trackInputs[i];
	      final clip = spec.clip;
	      final clipDuration = spec.clipDuration;

	      final gap = clip.startTime - currentDuration;
	      if (gap > Duration.zero) {
	        final gapLabel = 'vgap_${trackIndex}_$i';
	        filters.add(
	          'color=c=black@0.0:s=${width}x$height:d=${_seconds(gap)},fps=$fps,format=rgba,setsar=1[$gapLabel]',
	        );
	        if (currentLabel == null) {
	          currentLabel = gapLabel;
	          currentDuration += gap;
        } else {
          final nextLabel = 'vseq_${trackIndex}_gap_$i';
          filters.add(
            '[$currentLabel][$gapLabel]concat=n=2:v=1:a=0,settb=1/$fps[$nextLabel]',
          );
          currentLabel = nextLabel;
          currentDuration += gap;
        }
      }

	      final clipLabel = 'vclip_${trackIndex}_$i';
	      final clipFilters = <String>[
	        'trim=start=${_seconds(clip.sourceStart)}:duration=${_seconds(clipDuration)}',
	        'setpts=PTS-STARTPTS',
	        'fps=$fps', // Normalize frame rate and timebase
	        'scale=$width:$height:force_original_aspect_ratio=decrease',
	        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2',
	        'setsar=1',
	      ];
	      clipFilters.addAll(_buildEffectFilters(clip.effects, fastPreview: fastPreview));
	      clipFilters.addAll(_buildFadeFiltersForClip(clip, clipDuration));
	      clipFilters.add('format=rgba');

	      filters.add(
	        '[${spec.inputIndex}:v]${clipFilters.join(',')}[$clipLabel]',
	      );
      var clipOutLabel = clipLabel;

	      if (currentLabel == null) {
	        currentLabel = clipLabel;
	        currentDuration += clipDuration;
	        previousClip = clip;
	        previousClipDuration = clipDuration;
	        continue;
	      }

	      final transition = _pickTransition(previousClip, clip);
	      if (transition != null && gap <= Duration.zero) {
	        final maxTransitionMs = min(previousClipDuration.inMilliseconds, clipDuration.inMilliseconds);
	        final maxTransition = Duration(milliseconds: maxTransitionMs);
	        final transitionDuration = transition.duration <= maxTransition
	            ? transition.duration
	            : maxTransition;
	        if (transitionDuration > Duration.zero) {
            // NOTE:
            // xfade intrinsically overlaps clips, which shortens the output timeline.
            // Our GUI timeline currently represents clips as non-overlapping blocks,
            // so using xfade when clips are just "butted" (gap == 0) causes a visible
            // desync between GUI positions and preview playback.
            //
            // We only use xfade when the timeline explicitly overlaps clips (gap < 0).
            // Otherwise we fall back to a simple fade-out/fade-in while keeping duration.
            if (gap < Duration.zero) {
              final prevNormLabel = 'vseq_${trackIndex}_xfadeprev_$i';
              filters.add('[$currentLabel]settb=1/$fps[$prevNormLabel]');
              final nextNormLabel = 'vseq_${trackIndex}_xfadenext_$i';
              filters.add('[$clipLabel]settb=1/$fps[$nextNormLabel]');

              final transitionName = _xfadeTransitionName(transition);
              final offset = max(
                0.0,
                _secondsDouble(currentDuration) - _secondsDouble(transitionDuration),
              );
              final nextLabel = 'vseq_${trackIndex}_xfade_$i';
              filters.add(
                '[$prevNormLabel][$nextNormLabel]'
                'xfade=transition=$transitionName:duration=${_seconds(transitionDuration)}'
                ':offset=${offset.toStringAsFixed(6)},settb=1/$fps[$nextLabel]',
              );
              currentLabel = nextLabel;
              currentDuration = currentDuration + clipDuration - transitionDuration;
              previousClip = clip;
              previousClipDuration = clipDuration;
              continue;
            } else {
              final fadeOutStart = max(
                0.0,
                _secondsDouble(currentDuration) - _secondsDouble(transitionDuration),
              );
              final prevFadedLabel = 'vseq_${trackIndex}_fadeprev_$i';
              filters.add(
                '[$currentLabel]'
                'fade=t=out:st=${fadeOutStart.toStringAsFixed(6)}:d=${_seconds(transitionDuration)}'
                '[$prevFadedLabel]',
              );
              currentLabel = prevFadedLabel;
              final clipFadeLabel = 'vclip_${trackIndex}_${i}_fadein';
              filters.add(
                '[$clipLabel]fade=t=in:st=0:d=${_seconds(transitionDuration)}[$clipFadeLabel]',
              );
              clipOutLabel = clipFadeLabel;
            }
	        }
	      }

      final nextLabel = 'vseq_${trackIndex}_$i';
      filters.add(
        '[$currentLabel][$clipOutLabel]concat=n=2:v=1:a=0,settb=1/$fps[$nextLabel]',
      );
	      currentLabel = nextLabel;
	      currentDuration += clipDuration;
	      previousClip = clip;
	      previousClipDuration = clipDuration;
	    }

    if (currentLabel == null) {
      return 'vbase0';
    }

    if (currentDuration < timelineDuration) {
      final padSeconds = _seconds(timelineDuration - currentDuration);
      final paddedLabel = 'vtrack_${trackIndex}_padded';
      filters.add(
        '[$currentLabel]tpad=stop_mode=clone:stop_duration=$padSeconds[$paddedLabel]',
      );
      return paddedLabel;
    }

    return currentLabel;
  }

  TransitionEffect? _pickTransition(Clip? previous, Clip current) {
    final currentTransition = current.inTransition;
    if (_isXfadeTransition(currentTransition)) {
      return currentTransition;
    }
    final previousTransition = previous?.outTransition;
    if (_isXfadeTransition(previousTransition)) {
      return previousTransition;
    }
    return null;
  }

  bool _isXfadeTransition(TransitionEffect? transition) {
    if (transition == null) return false;
    switch (transition.type) {
      case TransitionType.fadeIn:
      case TransitionType.fadeOut:
        return false;
      case TransitionType.crossFade:
      case TransitionType.wipe:
      case TransitionType.slide:
      case TransitionType.zoom:
        return true;
    }
  }

  List<String> _buildEffectFilters(
    List<Effect> effects, {
    required bool fastPreview,
  }) {
    // Deduplicate effects by type - only use the last effect of each type
    // This prevents accidental stacking when users modify effect settings
    final effectsByType = <String, Effect>{};
    for (final effect in effects) {
      effectsByType[effect.type] = effect;
    }

    final filters = <String>[];
    for (final effect in effectsByType.values) {
      final filter = _effectFilter(effect, fastPreview: fastPreview);
      if (filter.isNotEmpty) {
        filters.add(filter);
      }
    }
    return filters;
  }

  List<String> _buildFadeFiltersForClip(Clip clip, Duration clipDuration) {
    final filters = <String>[];
    if (clip.inTransition?.type == TransitionType.fadeIn) {
      final duration =
          _transitionDuration(clip.inTransition!.duration, clipDuration, clipDuration);
      if (duration > Duration.zero) {
        filters.add('fade=t=in:st=0:d=${_seconds(duration)}');
      }
    }
    if (clip.outTransition?.type == TransitionType.fadeOut) {
      final duration =
          _transitionDuration(clip.outTransition!.duration, clipDuration, clipDuration);
      if (duration > Duration.zero) {
        final start = max(0.0, _secondsDouble(clipDuration) - _secondsDouble(duration));
        filters.add('fade=t=out:st=${start.toStringAsFixed(3)}:d=${_seconds(duration)}');
      }
    }
    return filters;
  }

  List<String> _buildAudioTransitionFilters(Clip clip, Duration clipDuration) {
    final filters = <String>[];
    if (clip.inTransition?.type == TransitionType.fadeIn) {
      final duration =
          _transitionDuration(clip.inTransition!.duration, clipDuration, clipDuration);
      if (duration > Duration.zero) {
        filters.add('afade=t=in:st=0:d=${_seconds(duration)}');
      }
    }
    if (clip.outTransition?.type == TransitionType.fadeOut) {
      final duration =
          _transitionDuration(clip.outTransition!.duration, clipDuration, clipDuration);
      if (duration > Duration.zero) {
        final start = max(0.0, _secondsDouble(clipDuration) - _secondsDouble(duration));
        filters.add('afade=t=out:st=${start.toStringAsFixed(3)}:d=${_seconds(duration)}');
      }
    }
    return filters;
  }

  Duration _transitionDuration(
    Duration requested,
    Duration clipDuration,
    Duration available,
  ) {
    if (requested <= Duration.zero) return Duration.zero;
    // For fade-in/fade-out style transitions, we can safely use up to the full
    // clip duration (clamped by any available handle length).
    final maxMs = min(clipDuration.inMilliseconds, available.inMilliseconds);
    final maxDuration = Duration(milliseconds: maxMs);
    return requested <= maxDuration ? requested : maxDuration;
  }

  Duration _clipDuration(Clip clip) {
    // Always use the actual clip duration (respects trimming)
    // clip.duration is calculated as endTime - startTime
    return clip.duration;
  }

  double _effectiveVolume(Track track, Clip clip) {
    if (clip.isMuted || track.isMuted) return 0.0;
    return (clip.volume * track.volume).clamp(0.0, 1.0);
  }

  bool _isMuted(Track track, Clip clip) {
    return track.isMuted || clip.isMuted;
  }

  Future<bool> _hasAudioStreamAsync(String filePath) async {
    try {
      final result = await Process.run(_ffprobe, [
        '-v',
        'error',
        '-select_streams',
        'a:0',
        '-show_entries',
        'stream=codec_type',
        '-of',
        'json',
        filePath,
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      final data = json.decode(result.stdout as String) as Map<String, dynamic>;
      final streams = data['streams'];
      return streams is List && streams.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _xfadeTransitionName(TransitionEffect effect) {
    switch (effect.type) {
      case TransitionType.fadeIn:
      case TransitionType.fadeOut:
      case TransitionType.crossFade:
        return 'fade';
      case TransitionType.wipe:
        switch (effect.parameters['direction']) {
          case 'right':
            return 'wiperight';
          case 'up':
            return 'wipeup';
          case 'down':
            return 'wipedown';
          default:
            return 'wipeleft';
        }
      case TransitionType.slide:
        switch (effect.parameters['direction']) {
          case 'right':
            return 'slideright';
          case 'up':
            return 'slideup';
          case 'down':
            return 'slidedown';
          default:
            return 'slideleft';
        }
      case TransitionType.zoom:
        // FFmpeg's xfade filter has `zoomin` but no `zoomout`.
        // For "out", use a visually similar built-in transition that is supported.
        final zoomType = effect.parameters['zoomType'] as String? ?? 'in';
        return zoomType == 'out' ? 'circleclose' : 'zoomin';
    }
  }

  Future<void> _runWithProgress(
    List<String> args,
    Duration totalDuration,
    Function(ExportProgress progress) onProgress,
  ) async {
    _cancelRequested = false;
    final process = await Process.start(_ffmpeg, args);
    _currentProcess = process;
    final totalMs = max(1, totalDuration.inMilliseconds);
    final startTime = DateTime.now();

    final stderrBuffer = StringBuffer();
    final stderrFuture = process.stderr
        .transform(utf8.decoder)
        .forEach((data) {
          stderrBuffer.write(data);
        });

    int? currentFrame;
    double? currentFps;
    int? currentTimeMs;
    int lastReportedPercentage = -1;

    final stdoutFuture = process.stdout
        .transform(utf8.decoder)
        .forEach((line) {
          for (final chunk in line.split('\n')) {
            if (chunk.startsWith('out_time_us=')) {
              // FFmpeg outputs time in microseconds, convert to milliseconds
              final timeUs = int.tryParse(chunk.split('=').last.trim()) ?? 0;
              currentTimeMs = timeUs ~/ 1000;
            } else if (chunk.startsWith('out_time_ms=')) {
              // Some FFmpeg versions output milliseconds directly
              currentTimeMs = int.tryParse(chunk.split('=').last.trim()) ?? 0;
            } else if (chunk.startsWith('frame=')) {
              currentFrame = int.tryParse(chunk.split('=').last.trim());
            } else if (chunk.startsWith('fps=')) {
              currentFps = double.tryParse(chunk.split('=').last.trim());
            }

            // Report progress when we have time information
            if (currentTimeMs != null && currentTimeMs! > 0 && totalMs > 0) {
              final progressValue = (currentTimeMs! / totalMs).clamp(0.0, 1.0);
              final currentPercentage = (progressValue * 100).round();

              // Only report progress if percentage changed significantly (at least 1%)
              // This reduces UI updates and makes progress smoother
              if (currentPercentage != lastReportedPercentage && currentPercentage >= 0) {
                lastReportedPercentage = currentPercentage;

                final elapsed = DateTime.now().difference(startTime);

                Duration? estimatedRemaining;
                if (progressValue > 0.001 && progressValue < 1.0) {
                  // Calculate remaining time: (elapsed / progress) * (1 - progress)
                  // This is more stable than: (elapsed / progress) - elapsed
                  final remainingRatio = (1.0 - progressValue) / progressValue;
                  final remainingMs = (elapsed.inMilliseconds * remainingRatio).round();
                  // Clamp to reasonable range (0 to 24 hours)
                  estimatedRemaining = Duration(milliseconds: remainingMs.clamp(0, 86400000));
                }

                onProgress(ExportProgress(
                  progress: progressValue,
                  currentFrame: currentFrame,
                  fps: currentFps,
                  elapsed: elapsed,
                  estimatedRemaining: estimatedRemaining,
                ));
              }
            }
          }
        });

    // Wait for both stdout and stderr to be fully read
    await Future.wait([stderrFuture, stdoutFuture]);

    final exitCode = await process.exitCode;
    _currentProcess = null;

    // Check if export was cancelled
    if (_cancelRequested) {
      throw Exception('Export cancelled by user');
    }

    if (exitCode != 0) {
      final errorMsg = stderrBuffer.toString();
      final argText = _formatArgsForError(args);
      throw Exception(
        'FFmpeg failed with exit code $exitCode\n\nError details:\n'
        '${errorMsg.isEmpty ? "No error output" : errorMsg}\n\nArgs:\n$argText',
      );
    }

    // Final progress report
    onProgress(ExportProgress(
      progress: 1.0,
      currentFrame: currentFrame,
      fps: currentFps,
      elapsed: DateTime.now().difference(startTime),
      estimatedRemaining: Duration.zero,
    ));
  }

  String _formatArgsForError(List<String> args) {
    final rendered = args
        .map((a) => a.contains(' ') ? '"${a.replaceAll('"', '\\"')}"' : a)
        .join(' ');
    const maxLen = 8000;
    if (rendered.length <= maxLen) return rendered;
    return '${rendered.substring(0, maxLen)}...';
  }

  double _secondsDouble(Duration duration) =>
      duration.inMilliseconds / 1000.0;

  String _seconds(Duration duration) =>
      (duration.inMilliseconds / 1000.0).toStringAsFixed(3);

  String _effectFilter(Effect effect, {required bool fastPreview}) {
    switch (effect.type) {
      case 'color_adjustment':
        final brightness =
            (effect.parameters['brightness'] as num?)?.toDouble() ?? 0.0;
        final contrast =
            (effect.parameters['contrast'] as num?)?.toDouble() ?? 0.0;
        final saturation =
            (effect.parameters['saturation'] as num?)?.toDouble() ?? 0.0;
        final intensity =
            (effect.parameters['intensity'] as num?)?.toDouble() ?? 1.0;
        return [
          'eq=brightness=${(brightness * intensity).toStringAsFixed(3)}'
          ':contrast=${(1.0 + contrast * intensity).toStringAsFixed(3)}'
          ':saturation=${(1.0 + saturation * intensity).toStringAsFixed(3)}',
        ].join(',');
      case 'filter':
        final filterType =
            (effect.parameters['filterType'] as String?)?.toLowerCase() ?? '';
        final intensity =
            (effect.parameters['intensity'] as num?)?.toDouble() ?? 1.0;
        if (filterType.contains('sepia')) {
          return 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131:0,eq=saturation=${(0.5 + 0.5 * intensity).toStringAsFixed(3)}';
        }
        if (filterType.contains('mono') || filterType.contains('monochrome')) {
          return 'hue=s=0,eq=contrast=${(1.0 + 0.2 * intensity).toStringAsFixed(3)}';
        }
        if (filterType.contains('vintage')) {
          return 'curves=preset=vintage,eq=saturation=${(0.9 + 0.3 * intensity).toStringAsFixed(3)}';
        }
        return '';
      case 'low_light_denoise':
        final settings = DenoiseSettings.fromJson(effect.parameters);
        return _buildDenoiseFilterChainFromSettings(
          settings,
          fastPreview: fastPreview,
        );
      case 'auto_denoise':
        final settings = DenoiseSettings.fromJson(effect.parameters);
        return _buildDenoiseFilterChainFromSettings(
          settings,
          fastPreview: fastPreview,
        );
      default:
        return '';
    }
  }

  String _buildCoreImageNoiseReductionFilter(DenoiseSettings settings) {
    // Core Image CINoiseReduction:
    // - inputNoiseLevel: 0..0.1 (default 0.02)
    // - inputSharpness: 0..2 (default 0.4)
    final noiseLevel =
        (settings.strength * settings.lumaStrength * 0.1).clamp(0.0, 0.1);

    final sharpness = settings.preserveDetails
        ? (0.4 + (1.0 - settings.strength) * 1.2).clamp(0.0, 2.0)
        : (0.2 + (1.0 - settings.strength) * 0.6).clamp(0.0, 2.0);

    return "coreimage=filter='CINoiseReduction"
        "@inputNoiseLevel=${noiseLevel.toStringAsFixed(4)}"
        "@inputSharpness=${sharpness.toStringAsFixed(3)}'";
  }

  String _buildDenoiseFilterChainFromSettings(
    DenoiseSettings settings, {
    required bool fastPreview,
  }) {
    if (Platform.isMacOS && settings.backend == DenoiseBackend.coreImage) {
      if (fastPreview) {
        return _buildCoreImageNoiseReductionFilter(settings);
      }

      final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
      final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
      final temporal = settings.temporalRadius.clamp(1, 5);

      return [
        'hqdn3d=$luma:$chroma:$temporal:$temporal',
        _buildCoreImageNoiseReductionFilter(settings),
      ].join(',');
    }

    if (settings.backend == DenoiseBackend.coreML) {
      // Core ML denoise is executed as an offline pre-render step; fall back to a
      // lightweight temporal/spatial filter when running in FFmpeg graphs.
      final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
      final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
      final temporal = settings.temporalRadius.clamp(1, 5);
      return 'hqdn3d=$luma:$chroma:$temporal:$temporal';
    }

    final filters = <String>[];

    // hqdn3d (base temporal/spatial filter) - always included for fast preview
    final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
    final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
    final temporal = settings.temporalRadius.clamp(1, 5);
    filters.add('hqdn3d=$luma:$chroma:$temporal:$temporal');

    // When fast preview is enabled, skip heavy filters for quicker startup.
    if (fastPreview) {
      return filters.join(',');
    }

    // nlmeans (non-local means) - high quality, preserves details
    if (settings.useNlmeans) {
      final strength = (settings.nlmeansStrength * 10).clamp(1.0, 10.0);
      final patchSize = settings.nlmeansPatchSize.clamp(3, 15);
      final researchSize = settings.nlmeansResearchSize.clamp(7, 31);
      filters.add('nlmeans=s=$strength:p=$patchSize:r=$researchSize');
    }

    // bm3d (block-matching 3D) - highest quality FFmpeg filter
    if (settings.useBm3d) {
      final sigma = settings.bm3dSigma.clamp(1.0, 20.0);
      filters.add('bm3d=sigma=$sigma');
    }

    // vaguedenoiser (wavelet-based) - for fine noise
    if (settings.useVaguedenoiser) {
      filters.add('vaguedenoiser=threshold=3:method=hard:nsteps=6');
    }

    // dctdnoiz (DCT-based) - for block artifacts
    if (settings.useDctdnoiz) {
      filters.add('dctdnoiz=sigma=15');
    }

    return filters.join(',');
  }

  int _getQualityCRF(Quality quality) {
    switch (quality) {
      case Quality.high:
        return 18;
      case Quality.standard:
        return 23;
      case Quality.low:
        return 28;
    }
  }

  String _bitrateArg(int bitrateBps) {
    if (bitrateBps <= 0) return '128k';
    final kbps = (bitrateBps / 1000.0).round().clamp(8, 512);
    return '${kbps}k';
  }

  /// Get appropriate bitrate for hardware encoders based on quality and resolution
  String _getQualityBitrate(Quality quality, int width, int height) {
    final pixelCount = width * height;

    // Bitrate calculation based on resolution and quality
    // These are approximate values optimized for hardware encoders
    double baseBitrate;

    if (pixelCount <= 640 * 480) {
      // SD (480p or lower)
      baseBitrate = quality == Quality.high ? 2.5 :
                    quality == Quality.standard ? 1.5 : 1.0;
    } else if (pixelCount <= 1280 * 720) {
      // HD (720p)
      baseBitrate = quality == Quality.high ? 5.0 :
                    quality == Quality.standard ? 3.0 : 2.0;
    } else if (pixelCount <= 1920 * 1080) {
      // Full HD (1080p)
      baseBitrate = quality == Quality.high ? 8.0 :
                    quality == Quality.standard ? 5.0 : 3.0;
    } else {
      // 4K and above
      baseBitrate = quality == Quality.high ? 25.0 :
                    quality == Quality.standard ? 15.0 : 10.0;
    }

    return '${baseBitrate.toStringAsFixed(1)}M';
  }
}

class _InputSpec {
  final int inputIndex;
  final MediaItem mediaItem;
  final Clip clip;
  final Track track;

  _InputSpec({
    required this.inputIndex,
    required this.mediaItem,
    required this.clip,
    required this.track,
  });

  Duration get clipDuration {
    // Always use the actual clip duration (respects trimming)
    // clip.duration is calculated as endTime - startTime
    return clip.duration;
  }
}

/// Progress information for video export
class ExportProgress {
  /// Progress value from 0.0 to 1.0
  final double progress;

  /// Current frame being processed
  final int? currentFrame;

  /// Current processing speed in frames per second
  final double? fps;

  /// Time elapsed since export started
  final Duration elapsed;

  /// Estimated time remaining (null if not enough data)
  final Duration? estimatedRemaining;

  const ExportProgress({
    required this.progress,
    this.currentFrame,
    this.fps,
    required this.elapsed,
    this.estimatedRemaining,
  });

  /// Get progress as percentage (0-100)
  int get percentage => (progress * 100).round();

  /// Format elapsed time as string (e.g., "01:23")
  String get elapsedFormatted => _formatDuration(elapsed);

  /// Format estimated remaining time as string (e.g., "02:45")
  String get remainingFormatted =>
      estimatedRemaining != null ? _formatDuration(estimatedRemaining!) : '--:--';

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class HlsPreviewSession {
  final Directory directory;
  final String playlistPath;
  final Duration startOffset;
  final Duration duration;
  final Process _process;

  HlsPreviewSession._({
    required this.directory,
    required this.playlistPath,
    required this.startOffset,
    required this.duration,
    required Process process,
  }) : _process = process;

  Future<int> get exitCode => _process.exitCode;

  Future<void> stop() async {
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _process.kill(ProcessSignal.sigkill);
    } catch (_) {}
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}
