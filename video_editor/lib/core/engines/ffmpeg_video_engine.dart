import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:path/path.dart' as path;
import 'package:video_editor/core/engines/video_engine.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/platform/coreml_denoise.dart';
import 'package:video_editor/core/models/denoise_level.dart';

/// FFmpeg-based video engine implementation using the system ffmpeg/ffprobe.
class FFmpegVideoEngine implements VideoEngine {
  FFmpegVideoEngine();

  static const _ffmpeg = 'ffmpeg';
  static const _ffprobe = 'ffprobe';

  String? _cachedHardwareEncoder;
  bool _hardwareEncoderChecked = false;

  @override
  Future<void> loadVideo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Video file not found', filePath);
    }
  }

  @override
  Future<VideoInfo> getVideoInfo(String filePath) async {
    final data = await _probe(filePath);
    final stream = _pickStream(data['streams'], 'video');
    if (stream == null) {
      throw Exception('No video stream found');
    }

    final width = (stream['width'] as num?)?.toInt() ?? 0;
    final height = (stream['height'] as num?)?.toInt() ?? 0;
    final durationSeconds = _parseDuration(data['format']?['duration']);
    final frameRate = _parseFrameRate(stream['r_frame_rate'] as String?);
    final codec = stream['codec_name'] as String? ?? 'unknown';
    final bitrate = int.tryParse('${stream['bit_rate'] ?? 0}') ?? 0;

    return VideoInfo(
      resolution: _mapResolution(Size(width.toDouble(), height.toDouble())),
      frameRate: frameRate,
      duration: durationSeconds,
      codec: codec,
      bitrate: bitrate,
    );
  }

  @override
  Future<AudioInfo> getAudioInfo(String filePath) async {
    final data = await _probe(filePath);
    final stream = _pickStream(data['streams'], 'audio');
    if (stream == null) {
      throw Exception('No audio stream found');
    }

    final durationSeconds = _parseDuration(data['format']?['duration']);
    final sampleRate =
        int.tryParse('${stream['sample_rate'] ?? 44100}') ?? 44100;
    final channels = (stream['channels'] as num?)?.toInt() ?? 2;
    final codec = stream['codec_name'] as String? ?? 'unknown';
    final bitrate = int.tryParse('${stream['bit_rate'] ?? 0}') ?? 0;

    return AudioInfo(
      sampleRate: sampleRate,
      channels: channels,
      duration: durationSeconds,
      codec: codec,
      bitrate: bitrate,
    );
  }

  @override
  Future<Uint8List> generateThumbnail(
    String filePath,
    Duration timestamp, {
    int width = 320,
    int height = 180,
  }) async {
    final args = [
      if (Platform.isMacOS) ...['-hwaccel', 'videotoolbox'],
      '-ss',
      _formatTimestamp(timestamp),
      '-i',
      filePath,
      '-vframes',
      '1',
      '-vf',
      'scale=$width:$height:force_original_aspect_ratio=decrease',
      '-f',
      'image2pipe',
      '-vcodec',
      'png',
      '-',
    ];

    try {
      final bytes = await _runAndCollect(_ffmpeg, args);
      return bytes;
    } catch (_) {
      if (!Platform.isMacOS) rethrow;
      final fallbackArgs = args
          .where((a) => a != 'videotoolbox' && a != '-hwaccel')
          .toList();
      final bytes = await _runAndCollect(_ffmpeg, fallbackArgs);
      return bytes;
    }
  }

  @override
  Future<void> applyEffect(
    String inputPath,
    String outputPath,
    Effect effect,
  ) async {
    final filter = _effectFilter(effect);
    await _run(_ffmpeg, [
      '-y',
      '-i',
      inputPath,
      if (filter.isNotEmpty) '-vf',
      if (filter.isNotEmpty) filter,
      '-c:a',
      'copy',
      outputPath,
    ]);
  }

  Future<void> renderClipWithEffects(
    String inputPath,
    String outputPath, {
    required Duration sourceStart,
    required Duration duration,
    required List<Effect> effects,
    TransitionEffect? inTransition,
    TransitionEffect? outTransition,
  }) async {
    var effectiveInputPath = inputPath;
    var effectiveSourceStart = sourceStart;
    var effectiveEffects = effects;

    Directory? coreMlTempDir;
    try {
      final coreMlEffect = effects.cast<Effect?>().firstWhere(
        (e) =>
            e != null &&
            (e.type == 'auto_denoise' || e.type == 'low_light_denoise') &&
            (DenoiseSettings.fromJson(e.parameters).backend ==
                    DenoiseBackend.coreML ||
                DenoiseSettings.fromJson(e.parameters).useAiModel) &&
            ((DenoiseSettings.fromJson(e.parameters).aiModelPath?.isNotEmpty ??
                false)),
        orElse: () => null,
      );

      if (Platform.isMacOS && coreMlEffect != null) {
        final s = DenoiseSettings.fromJson(coreMlEffect.parameters);
        final modelPath = s.aiModelPath!;
        if (File(modelPath).existsSync() || Directory(modelPath).existsSync()) {
          coreMlTempDir = await Directory.systemTemp.createTemp(
            'video_editor_coreml_clip_',
          );
          final denoisedPath = path.join(coreMlTempDir.path, 'denoised.mp4');

          await CoreMlDenoise.denoiseVideo(
            inputPath: inputPath,
            outputPath: denoisedPath,
            sourceStart: sourceStart,
            duration: duration,
            modelPath: modelPath,
          );

          effectiveInputPath = denoisedPath;
          effectiveSourceStart = Duration.zero;
          effectiveEffects = effects
              .where(
                (e) =>
                    e.type != 'auto_denoise' && e.type != 'low_light_denoise',
              )
              .toList();
        }
      }

      final filters = effectiveEffects
          .map(_effectFilter)
          .where((f) => f.trim().isNotEmpty)
          .toList();

      // Add transition filters
      if (inTransition?.type == TransitionType.fadeIn) {
        final fadeInDuration = _clampDuration(inTransition!.duration, duration);
        if (fadeInDuration > Duration.zero) {
          filters.add('fade=t=in:st=0:d=${_formatTimestamp(fadeInDuration)}');
        }
      }
      if (outTransition?.type == TransitionType.fadeOut) {
        final fadeOutDuration = _clampDuration(
          outTransition!.duration,
          duration,
        );
        if (fadeOutDuration > Duration.zero) {
          final startTime = duration - fadeOutDuration;
          filters.add(
            'fade=t=out:st=${_formatTimestamp(startTime)}:d=${_formatTimestamp(fadeOutDuration)}',
          );
        }
      }

      final chain = filters.join(',');

      // Build audio transition filters
      final audioFilters = <String>[];
      if (inTransition?.type == TransitionType.fadeIn) {
        final fadeInDuration = _clampDuration(inTransition!.duration, duration);
        if (fadeInDuration > Duration.zero) {
          audioFilters.add(
            'afade=t=in:st=0:d=${_formatTimestamp(fadeInDuration)}',
          );
        }
      }
      if (outTransition?.type == TransitionType.fadeOut) {
        final fadeOutDuration = _clampDuration(
          outTransition!.duration,
          duration,
        );
        if (fadeOutDuration > Duration.zero) {
          final startTime = duration - fadeOutDuration;
          audioFilters.add(
            'afade=t=out:st=${_formatTimestamp(startTime)}:d=${_formatTimestamp(fadeOutDuration)}',
          );
        }
      }
      final audioChain = audioFilters.join(',');

      final hardwareEncoder = await _detectHardwareEncoder();
      final useHardware = hardwareEncoder != null;

      final args = <String>[
        '-y',
        '-ss',
        _formatTimestamp(effectiveSourceStart),
        '-t',
        _formatTimestamp(duration),
        '-i',
        effectiveInputPath,
        if (chain.isNotEmpty) ...['-vf', chain],
        if (audioChain.isNotEmpty) ...['-af', audioChain],
        '-c:v',
        useHardware ? hardwareEncoder : 'libx264',
        if (useHardware) ...[
          '-b:v',
          '4M',
          '-maxrate',
          '4M',
          if (hardwareEncoder == 'h264_videotoolbox') ...['-allow_sw', '1'],
        ] else ...[
          '-preset',
          'veryfast',
          '-crf',
          '23',
        ],
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        outputPath,
      ];

      await _run(_ffmpeg, args);
    } finally {
      try {
        if (coreMlTempDir != null && await coreMlTempDir.exists()) {
          await coreMlTempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<String?> _detectHardwareEncoder() async {
    if (_hardwareEncoderChecked) {
      return _cachedHardwareEncoder;
    }

    _hardwareEncoderChecked = true;

    try {
      final result = await Process.run(_ffmpeg, ['-hide_banner', '-encoders']);

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout as String;
      final encodersToTry = [
        'h264_videotoolbox', // macOS VideoToolbox
        'h264_nvenc', // NVIDIA GPU
        'h264_qsv', // Intel Quick Sync Video
        'h264_vaapi', // Linux VA-API
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

  @override
  Future<void> applyDenoise(
    String inputPath,
    String outputPath,
    DenoiseSettings settings,
  ) async {
    final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
    final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
    final temporal = settings.temporalRadius.clamp(1, 5);
    final filter = 'hqdn3d=$luma:$chroma:$temporal:$temporal';

    await _run(_ffmpeg, [
      '-y',
      '-i',
      inputPath,
      '-vf',
      filter,
      '-c:a',
      'copy',
      outputPath,
    ]);
  }

  @override
  Future<List<double>> extractWaveform(
    String audioPath, {
    int sampleCount = 1000,
  }) async {
    final args = [
      '-i',
      audioPath,
      '-ac',
      '1',
      '-ar',
      '44100',
      '-f',
      's16le',
      '-',
    ];

    final bytes = await _runAndCollect(_ffmpeg, args);
    if (bytes.isEmpty) {
      return [];
    }

    const sampleBytes = 2;
    final totalSamples = bytes.length ~/ sampleBytes;
    if (totalSamples == 0) return [];

    final stride = max(1, totalSamples ~/ sampleCount);
    final waveform = <double>[];
    final data = ByteData.sublistView(bytes);

    for (int i = 0; i < totalSamples; i += stride) {
      final offset = i * sampleBytes;
      if (offset + 1 >= bytes.length) break;
      final value = data.getInt16(offset, Endian.little);
      waveform.add(value / 32768.0);
      if (waveform.length >= sampleCount) break;
    }

    return waveform;
  }

  @override
  Future<void> dispose() async {
    // No-op for CLI based engine.
  }

  Future<Map<String, dynamic>> _probe(String filePath) async {
    final result = await _run(_ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration:stream=index,codec_type,codec_name,width,height,r_frame_rate,bit_rate,channels,sample_rate',
      '-of',
      'json',
      filePath,
    ]);

    return json.decode(result.stdout as String) as Map<String, dynamic>;
  }

  Map<String, dynamic>? _pickStream(dynamic streams, String type) {
    if (streams is! List) return null;
    for (final stream in streams) {
      if (stream is Map<String, dynamic> && stream['codec_type'] == type) {
        return stream;
      }
    }
    return null;
  }

  Future<ProcessResult> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw Exception('$executable failed: ${result.stderr ?? result.stdout}');
    }
    return result;
  }

  Future<Uint8List> _runAndCollect(String executable, List<String> args) async {
    final process = await Process.start(executable, args);
    final bytes = <int>[];
    process.stdout.listen(bytes.addAll);
    final stderr = StringBuffer();
    await process.stderr.transform(utf8.decoder).forEach(stderr.write);
    final code = await process.exitCode;
    if (code != 0) {
      throw Exception('$executable failed: $stderr');
    }
    return Uint8List.fromList(bytes);
  }

  Duration _parseDuration(dynamic value) {
    final seconds = double.tryParse('${value ?? 0}') ?? 0.0;
    final millis = (seconds * 1000).round();
    return Duration(milliseconds: millis);
  }

  int _parseFrameRate(String? value) {
    if (value == null || value.isEmpty) return 30;
    if (!value.contains('/')) {
      return int.tryParse(value) ?? 30;
    }
    final parts = value.split('/');
    if (parts.length != 2) return 30;
    final num = double.tryParse(parts[0]) ?? 0;
    final den = double.tryParse(parts[1]) ?? 1;
    if (den == 0) return 30;
    return (num / den).round();
  }

  Resolution _mapResolution(Size size) {
    final height = size.height.round();
    if (height >= Resolution.r4k.height) {
      return Resolution.r4k;
    }
    if (height >= Resolution.r1080p.height) {
      return Resolution.r1080p;
    }
    if (height >= Resolution.r720p.height) {
      return Resolution.r720p;
    }
    return Resolution.r480p;
  }

  String _formatTimestamp(Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    return seconds.toStringAsFixed(3);
  }

  Duration _clampDuration(Duration requested, Duration maximum) {
    if (requested <= Duration.zero) return Duration.zero;
    final maxMs = maximum.inMilliseconds;
    final requestedMs = requested.inMilliseconds;
    return requestedMs <= maxMs ? requested : maximum;
  }

  String _buildCoreImageNoiseReductionFilter(DenoiseSettings settings) {
    final noiseLevel = (settings.strength * settings.lumaStrength * 0.1).clamp(
      0.0,
      0.1,
    );

    final sharpness = settings.preserveDetails
        ? (0.4 + (1.0 - settings.strength) * 1.2).clamp(0.0, 2.0)
        : (0.2 + (1.0 - settings.strength) * 0.6).clamp(0.0, 2.0);

    return "coreimage=filter='CINoiseReduction"
        "@inputNoiseLevel=${noiseLevel.toStringAsFixed(4)}"
        "@inputSharpness=${sharpness.toStringAsFixed(3)}'";
  }

  String _buildDenoiseFilterChainFromSettings(DenoiseSettings settings) {
    if (Platform.isMacOS && settings.backend == DenoiseBackend.coreImage) {
      final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
      final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
      final temporal = settings.temporalRadius.clamp(1, 5);
      return [
        'hqdn3d=$luma:$chroma:$temporal:$temporal',
        _buildCoreImageNoiseReductionFilter(settings),
      ].join(',');
    }

    if (settings.backend == DenoiseBackend.coreML) {
      final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
      final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
      final temporal = settings.temporalRadius.clamp(1, 5);
      return 'hqdn3d=$luma:$chroma:$temporal:$temporal';
    }

    final filters = <String>[];

    final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
    final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
    final temporal = settings.temporalRadius.clamp(1, 5);
    filters.add('hqdn3d=$luma:$chroma:$temporal:$temporal');

    if (settings.useNlmeans) {
      final strength = (settings.nlmeansStrength * 10).clamp(1.0, 10.0);
      final patchSize = settings.nlmeansPatchSize.clamp(3, 15);
      final researchSize = settings.nlmeansResearchSize.clamp(7, 31);
      filters.add('nlmeans=s=$strength:p=$patchSize:r=$researchSize');
    }

    if (settings.useBm3d) {
      final sigma = settings.bm3dSigma.clamp(1.0, 20.0);
      filters.add('bm3d=sigma=$sigma');
    }

    if (settings.useVaguedenoiser) {
      filters.add('vaguedenoiser=threshold=3:method=hard:nsteps=6');
    }

    if (settings.useDctdnoiz) {
      filters.add('dctdnoiz=sigma=15');
    }

    return filters.join(',');
  }

  String _effectFilter(Effect effect) {
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
        final eq = [
          'brightness=${brightness * intensity}',
          'contrast=${1.0 + contrast * intensity}',
          'saturation=${1.0 + saturation * intensity}',
        ].join(':');
        return 'eq=$eq';
      case 'filter':
        final filterType =
            (effect.parameters['filterType'] as String?)?.toLowerCase() ?? '';
        final intensity =
            (effect.parameters['intensity'] as num?)?.toDouble() ?? 1.0;
        if (filterType.contains('sepia')) {
          return 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131:0,format=yuv420p,eq=saturation=${0.5 + 0.5 * intensity}';
        }
        if (filterType.contains('mono') || filterType.contains('monochrome')) {
          return 'hue=s=0,eq=contrast=${1.0 + 0.2 * intensity}';
        }
        if (filterType.contains('vintage')) {
          return 'curves=preset=vintage,eq=saturation=${0.9 + 0.3 * intensity}';
        }
        return '';
      case 'low_light_denoise':
        final settings = DenoiseSettings.fromJson(effect.parameters);
        return _buildDenoiseFilterChainFromSettings(settings);
      case 'auto_denoise':
        final settings = DenoiseSettings.fromJson(effect.parameters);
        return _buildDenoiseFilterChainFromSettings(settings);
      default:
        return '';
    }
  }
}
