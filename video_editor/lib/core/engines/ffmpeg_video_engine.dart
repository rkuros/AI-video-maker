import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:video_editor/core/engines/video_engine.dart';
import 'package:video_editor/core/models/models.dart';

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

    final bytes = await _runAndCollect(_ffmpeg, args);
    return bytes;
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
  }) async {
    final chain = effects
        .map(_effectFilter)
        .where((f) => f.trim().isNotEmpty)
        .join(',');

    final hardwareEncoder = await _detectHardwareEncoder();
    final useHardware = hardwareEncoder != null;

    final args = <String>[
      '-y',
      '-ss',
      _formatTimestamp(sourceStart),
      '-t',
      _formatTimestamp(duration),
      '-i',
      inputPath,
      if (chain.isNotEmpty) ...['-vf', chain],
      '-c:v',
      useHardware ? hardwareEncoder : 'libx264',
      if (useHardware) ...[
        '-b:v',
        '4M',
        '-maxrate',
        '4M',
        if (hardwareEncoder == 'h264_videotoolbox') ...[
          '-allow_sw',
          '1',
        ],
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
  }

  Future<String?> _detectHardwareEncoder() async {
    if (_hardwareEncoderChecked) {
      return _cachedHardwareEncoder;
    }

    _hardwareEncoderChecked = true;

    try {
      final result = await Process.run(_ffmpeg, [
        '-hide_banner',
        '-encoders',
      ]);

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
      throw Exception(
        '$executable failed: ${result.stderr ?? result.stdout}',
      );
    }
    return result;
  }

  Future<Uint8List> _runAndCollect(
    String executable,
    List<String> args,
  ) async {
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

  String _effectFilter(Effect effect) {
    switch (effect.type) {
      case 'color_adjustment':
        final brightness = (effect.parameters['brightness'] as num?)?.toDouble() ?? 0.0;
        final contrast = (effect.parameters['contrast'] as num?)?.toDouble() ?? 0.0;
        final saturation = (effect.parameters['saturation'] as num?)?.toDouble() ?? 0.0;
        final intensity = (effect.parameters['intensity'] as num?)?.toDouble() ?? 1.0;
        final eq = [
          'brightness=${brightness * intensity}',
          'contrast=${1.0 + contrast * intensity}',
          'saturation=${1.0 + saturation * intensity}',
        ].join(':');
        return 'eq=$eq';
      case 'filter':
        final filterType = (effect.parameters['filterType'] as String?)?.toLowerCase() ?? '';
        final intensity = (effect.parameters['intensity'] as num?)?.toDouble() ?? 1.0;
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
        final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
        final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
        final temporal = settings.temporalRadius.clamp(1, 5);
        return 'hqdn3d=$luma:$chroma:$temporal:$temporal';
      case 'auto_denoise':
        final settings = DenoiseSettings.fromJson(effect.parameters);
        final filters = <String>[];

        // hqdn3d (base)
        final luma = (settings.lumaStrength * 5).clamp(0.1, 5.0);
        final chroma = (settings.chromaStrength * 5).clamp(0.1, 5.0);
        final temporal = settings.temporalRadius.clamp(1, 5);
        filters.add('hqdn3d=$luma:$chroma:$temporal:$temporal');

        // Additional filters based on settings
        if (settings.useNlmeans) {
          final strength = (settings.nlmeansStrength * 10).clamp(1.0, 10.0);
          filters.add('nlmeans=s=$strength:p=${settings.nlmeansPatchSize}:r=${settings.nlmeansResearchSize}');
        }
        if (settings.useBm3d) {
          filters.add('bm3d=sigma=${settings.bm3dSigma}');
        }
        if (settings.useVaguedenoiser) {
          filters.add('vaguedenoiser=threshold=3:method=hard:nsteps=6');
        }
        if (settings.useDctdnoiz) {
          filters.add('dctdnoiz=sigma=15');
        }

        return filters.join(',');
      default:
        return '';
    }
  }
}
