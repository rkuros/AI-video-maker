import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';

/// Service for extracting audio features from videos
class AudioFeatureExtractor {
  /// Extract audio from video and save as WAV
  Future<String?> extractAudio(
    String videoPath, {
    Duration startTime = Duration.zero,
    Duration? duration,
  }) async {
    final tempDir = Directory.systemTemp.path;
    final audioPath =
        '$tempDir/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    final result = await Process.run('ffmpeg', [
      if (startTime > Duration.zero) ...[
        '-ss',
        (startTime.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      if (duration != null && duration > Duration.zero) ...[
        '-t',
        (duration.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      '-i', videoPath,
      '-vn', // No video
      '-acodec', 'pcm_s16le', // 16-bit PCM
      '-ar', '44100', // 44.1kHz sample rate
      '-ac', '1', // Mono
      audioPath,
    ]);

    if (result.exitCode == 0 && File(audioPath).existsSync()) {
      return audioPath;
    }

    return null;
  }

  /// Analyze volume levels throughout the video
  Future<List<VolumeSegment>> analyzeVolume(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 30,
  }) async {
    final result = await analyzeVolumeAndEnergy(
      videoPath,
      videoDuration,
      startTime: startTime,
      samplePoints: samplePoints,
    );
    return result.volumeSegments;
  }

  /// Detect beats in audio
  Future<List<Beat>> detectBeats(
    String videoPath, {
    Duration startTime = Duration.zero,
    Duration? duration,
  }) async {
    final beats = <Beat>[];

    // Use FFmpeg's silencedetect to find beat candidates
    // This is a simplified approach - real beat detection would use spectral analysis
    final result = await Process.run('ffmpeg', [
      if (startTime > Duration.zero) ...[
        '-ss',
        (startTime.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      if (duration != null && duration > Duration.zero) ...[
        '-t',
        (duration.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      '-i',
      videoPath,
      '-vn',
      '-af',
      'silencedetect=n=-30dB:d=0.1',
      '-f',
      'null',
      '-',
    ]);

    final output = result.stderr.toString();
    final lines = output.split('\n');

    Duration? lastSilenceEnd;
    for (final line in lines) {
      final silenceEndMatch = RegExp(
        r'silence_end:\s*([\d.]+)',
      ).firstMatch(line);
      if (silenceEndMatch != null) {
        final timestamp = double.parse(silenceEndMatch.group(1)!);
        final duration = Duration(milliseconds: (timestamp * 1000).round());

        // If there was a previous silence end, calculate tempo
        double? tempo;
        if (lastSilenceEnd != null) {
          final interval =
              duration.inMilliseconds - lastSilenceEnd.inMilliseconds;
          if (interval > 0) {
            tempo = 60000.0 / interval; // BPM
          }
        }

        beats.add(
          Beat(
            timestamp: duration,
            strength: 0.7, // Default strength
            tempo: tempo,
          ),
        );

        lastSilenceEnd = duration;
      }
    }

    return beats;
  }

  /// Analyze frequency spectrum
  Future<List<FrequencySegment>> analyzeFrequency(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 20,
  }) async {
    final frequencySegments = <FrequencySegment>[];

    // Extract audio first
    final audioPath = await extractAudio(
      videoPath,
      startTime: startTime,
      duration: videoDuration,
    );
    if (audioPath == null) {
      return frequencySegments;
    }

    try {
      // Read audio samples
      final samples = await _readAudioSamples(audioPath, samplePoints);

      for (int i = 0; i < samples.length; i++) {
        final sampleData = samples[i];
        final timestamp = Duration(
          milliseconds: (videoDuration.inMilliseconds * i / samples.length)
              .round(),
        );

        // Perform FFT
        final spectrum = _performFFT(sampleData);

        frequencySegments.add(
          FrequencySegment(
            timestamp: timestamp,
            lowFrequency: spectrum['low']!,
            midFrequency: spectrum['mid']!,
            highFrequency: spectrum['high']!,
          ),
        );
      }
    } finally {
      // Clean up audio file
      try {
        await File(audioPath).delete();
      } catch (_) {}
    }

    return frequencySegments;
  }

  /// Detect speech in audio
  Future<List<SpeechSegment>> detectSpeech(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
  }) async {
    final speechSegments = <SpeechSegment>[];

    // Use FFmpeg's silencedetect to find non-silent segments (potential speech)
    final result = await Process.run('ffmpeg', [
      if (startTime > Duration.zero) ...[
        '-ss',
        (startTime.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      if (videoDuration > Duration.zero) ...[
        '-t',
        (videoDuration.inMilliseconds / 1000.0).toStringAsFixed(2),
      ],
      '-i',
      videoPath,
      '-vn',
      '-af',
      'silencedetect=n=-35dB:d=0.3',
      '-f',
      'null',
      '-',
    ]);

    final output = result.stderr.toString();
    final lines = output.split('\n');

    Duration? speechStart;
    for (final line in lines) {
      final silenceStartMatch = RegExp(
        r'silence_start:\s*([\d.]+)',
      ).firstMatch(line);
      final silenceEndMatch = RegExp(
        r'silence_end:\s*([\d.]+)',
      ).firstMatch(line);

      if (silenceEndMatch != null) {
        // Speech starts after silence ends
        final timestamp = double.parse(silenceEndMatch.group(1)!);
        speechStart = Duration(milliseconds: (timestamp * 1000).round());
      } else if (silenceStartMatch != null && speechStart != null) {
        // Speech ends when silence starts
        final timestamp = double.parse(silenceStartMatch.group(1)!);
        final speechEnd = Duration(milliseconds: (timestamp * 1000).round());

        // Only include segments longer than 0.5 seconds
        if ((speechEnd - speechStart).inMilliseconds > 500) {
          speechSegments.add(
            SpeechSegment(
              startTime: speechStart,
              endTime: speechEnd,
              confidence: 0.7, // Simplified confidence
              hasSpeech: true,
            ),
          );
        }

        speechStart = null;
      }
    }

    return speechSegments;
  }

  /// Calculate energy/excitement level
  Future<List<EnergySegment>> analyzeEnergy(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 30,
  }) async {
    final result = await analyzeVolumeAndEnergy(
      videoPath,
      videoDuration,
      startTime: startTime,
      samplePoints: samplePoints,
    );
    return result.energySegments;
  }

  Future<
    ({List<VolumeSegment> volumeSegments, List<EnergySegment> energySegments})
  >
  analyzeVolumeAndEnergy(
    String videoPath,
    Duration videoDuration, {
    Duration startTime = Duration.zero,
    int samplePoints = 30,
  }) async {
    // Extract audio once and reuse.
    final audioPath = await extractAudio(
      videoPath,
      startTime: startTime,
      duration: videoDuration,
    );
    if (audioPath == null) {
      return (
        volumeSegments: <VolumeSegment>[],
        energySegments: <EnergySegment>[],
      );
    }

    try {
      final volumeSegments = await _analyzeVolumeFromWav(
        audioPath,
        videoDuration,
        samplePoints: samplePoints,
      );
      final frequencySegments = await _analyzeFrequencyFromWav(
        audioPath,
        videoDuration,
        samplePoints: samplePoints,
      );

      final energySegments = <EnergySegment>[];
      for (
        int i = 0;
        i < min(volumeSegments.length, frequencySegments.length);
        i++
      ) {
        final volume = volumeSegments[i];
        final frequency = frequencySegments[i];

        final volumeEnergy = (volume.meanVolume + volume.maxVolume) / 2;
        final frequencyEnergy =
            (frequency.midFrequency + frequency.highFrequency) / 2;
        final energy = (volumeEnergy * 0.6 + frequencyEnergy * 0.4);

        energySegments.add(
          EnergySegment(
            startTime: volume.startTime,
            endTime: volume.endTime,
            energy: energy,
            excitement: energy,
          ),
        );
      }

      return (volumeSegments: volumeSegments, energySegments: energySegments);
    } finally {
      try {
        await File(audioPath).delete();
      } catch (_) {}
    }
  }

  Future<List<VolumeSegment>> _analyzeVolumeFromWav(
    String audioPath,
    Duration videoDuration, {
    required int samplePoints,
  }) async {
    final samples = await _readAudioSamples(audioPath, samplePoints);
    if (samples.isEmpty) return const [];

    final volumeSegments = <VolumeSegment>[];
    for (int i = 0; i < samples.length; i++) {
      final window = samples[i];
      if (window.isEmpty) continue;

      final rms = _rms(window);
      final peak = _peak(window);

      final meanDb = _toDb(rms);
      final maxDb = _toDb(peak);

      volumeSegments.add(
        VolumeSegment(
          startTime: Duration(
            milliseconds: (videoDuration.inMilliseconds * i / samples.length)
                .round(),
          ),
          endTime: Duration(
            milliseconds:
                (videoDuration.inMilliseconds * (i + 1) / samples.length)
                    .round(),
          ),
          meanVolume: _normalizeVolume(meanDb),
          maxVolume: _normalizeVolume(maxDb),
        ),
      );
    }
    return volumeSegments;
  }

  Future<List<FrequencySegment>> _analyzeFrequencyFromWav(
    String audioPath,
    Duration videoDuration, {
    required int samplePoints,
  }) async {
    final frequencySegments = <FrequencySegment>[];
    final samples = await _readAudioSamples(audioPath, samplePoints);
    if (samples.isEmpty) return frequencySegments;

    for (int i = 0; i < samples.length; i++) {
      final sampleData = samples[i];
      final timestamp = Duration(
        milliseconds: (videoDuration.inMilliseconds * i / samples.length)
            .round(),
      );

      final spectrum = _performFFT(sampleData);
      frequencySegments.add(
        FrequencySegment(
          timestamp: timestamp,
          lowFrequency: spectrum['low']!,
          midFrequency: spectrum['mid']!,
          highFrequency: spectrum['high']!,
        ),
      );
    }

    return frequencySegments;
  }

  double _rms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    var sumSq = 0.0;
    for (final s in samples) {
      sumSq += s * s;
    }
    return sqrt(sumSq / samples.length);
  }

  double _peak(List<double> samples) {
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return peak;
  }

  double _toDb(double amplitude) {
    if (amplitude <= 0) return -90.0;
    return (20.0 * log(amplitude) / ln10).clamp(-90.0, 0.0);
  }

  /// Read audio samples from WAV file
  Future<List<List<double>>> _readAudioSamples(
    String audioPath,
    int sampleCount,
  ) async {
    final samples = <List<double>>[];

    try {
      final file = File(audioPath);
      final bytes = await file.readAsBytes();

      // Skip WAV header (44 bytes)
      final audioData = bytes.sublist(44);

      // Convert bytes to 16-bit PCM samples
      final pcmSamples = <double>[];
      for (int i = 0; i < audioData.length - 1; i += 2) {
        final sample = (audioData[i] | (audioData[i + 1] << 8));
        // Convert to signed and normalize to -1.0 to 1.0
        final normalizedSample = sample > 32767 ? sample - 65536 : sample;
        pcmSamples.add(normalizedSample / 32768.0);
      }

      // Split into segments
      final samplesPerSegment = pcmSamples.length ~/ sampleCount;
      for (int i = 0; i < sampleCount; i++) {
        final start = i * samplesPerSegment;
        final end = min(start + samplesPerSegment, pcmSamples.length);
        samples.add(pcmSamples.sublist(start, end));
      }
    } catch (e) {
      print('Error reading audio samples: $e');
    }

    return samples;
  }

  /// Perform FFT on audio samples
  Map<String, double> _performFFT(List<double> samples) {
    // Ensure power of 2 length for FFT
    int fftSize = 1024;
    while (fftSize < samples.length) {
      fftSize *= 2;
    }

    // Pad or truncate to fftSize
    final paddedSamples = List<double>.filled(fftSize, 0.0);
    for (int i = 0; i < min(samples.length, fftSize); i++) {
      paddedSamples[i] = samples[i];
    }

    // Perform FFT
    final fft = FFT(fftSize);
    final complexInput = Float64x2List.fromList(
      List.generate(fftSize, (i) => Float64x2(paddedSamples[i], 0)),
    );

    fft.inPlaceFft(complexInput);

    // Calculate magnitude spectrum
    final magnitudes = <double>[];
    for (int i = 0; i < fftSize ~/ 2; i++) {
      final real = complexInput[i].x;
      final imag = complexInput[i].y;
      final magnitude = sqrt(real * real + imag * imag);
      magnitudes.add(magnitude);
    }

    // Divide into frequency bands
    // Assuming 44.1kHz sample rate
    final lowBand = magnitudes.sublist(0, magnitudes.length ~/ 4);
    final midBand = magnitudes.sublist(
      magnitudes.length ~/ 4,
      magnitudes.length ~/ 2,
    );
    final highBand = magnitudes.sublist(magnitudes.length ~/ 2);

    return {
      'low': _averageMagnitude(lowBand),
      'mid': _averageMagnitude(midBand),
      'high': _averageMagnitude(highBand),
    };
  }

  /// Calculate average magnitude and normalize
  double _averageMagnitude(List<double> magnitudes) {
    if (magnitudes.isEmpty) return 0.0;
    final avg = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    // Normalize to 0-1 range (assuming max magnitude of 100)
    return (avg / 100.0).clamp(0.0, 1.0);
  }

  /// Normalize volume from dB to 0-1 range
  /// -90 dB (silence) = 0.0, -10 dB (loud) = 1.0
  double _normalizeVolume(double volumeDB) {
    // Map -90 to -10 dB range to 0-1
    return ((volumeDB + 90) / 80).clamp(0.0, 1.0);
  }
}

/// Volume analysis result
class VolumeSegment {
  final Duration startTime;
  final Duration endTime;
  final double meanVolume; // 0-1, normalized
  final double maxVolume; // 0-1, normalized

  const VolumeSegment({
    required this.startTime,
    required this.endTime,
    required this.meanVolume,
    required this.maxVolume,
  });
}

/// Beat detection result
class Beat {
  final Duration timestamp;
  final double strength; // 0-1
  final double? tempo; // BPM

  const Beat({required this.timestamp, required this.strength, this.tempo});
}

/// Frequency analysis result
class FrequencySegment {
  final Duration timestamp;
  final double lowFrequency; // 0-1, bass
  final double midFrequency; // 0-1, mids
  final double highFrequency; // 0-1, treble

  const FrequencySegment({
    required this.timestamp,
    required this.lowFrequency,
    required this.midFrequency,
    required this.highFrequency,
  });

  double get overallActivity {
    return (lowFrequency + midFrequency + highFrequency) / 3;
  }
}

/// Speech detection result
class SpeechSegment {
  final Duration startTime;
  final Duration endTime;
  final double confidence; // 0-1
  final bool hasSpeech;

  const SpeechSegment({
    required this.startTime,
    required this.endTime,
    required this.confidence,
    required this.hasSpeech,
  });
}

/// Energy/excitement analysis result
class EnergySegment {
  final Duration startTime;
  final Duration endTime;
  final double energy; // 0-1, overall audio energy
  final double excitement; // 0-1, excitement level

  const EnergySegment({
    required this.startTime,
    required this.endTime,
    required this.energy,
    required this.excitement,
  });
}
