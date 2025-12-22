import 'package:flutter/material.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/highlight_generator_service.dart';

class HighlightGenerationRequest {
  final HighlightGenerationMode mode;
  final Duration targetDuration;
  final HighlightPattern pattern;
  final HighlightPreferences preferences;
  final MediaItem? bgm;

  const HighlightGenerationRequest({
    required this.mode,
    required this.targetDuration,
    required this.pattern,
    required this.preferences,
    required this.bgm,
  });
}

class HighlightGenerationDialog extends StatefulWidget {
  final List<MediaItem> mediaLibrary;

  const HighlightGenerationDialog({super.key, required this.mediaLibrary});

  @override
  State<HighlightGenerationDialog> createState() =>
      _HighlightGenerationDialogState();
}

class _HighlightGenerationDialogState extends State<HighlightGenerationDialog> {
  HighlightGenerationMode _mode = HighlightGenerationMode.pattern;
  HighlightPattern _pattern = HighlightPattern.vlog;
  Duration _duration = const Duration(seconds: 30);
  MediaItem? _bgm;

  bool _preferHighMotion = true;
  bool _preferFaces = true;
  bool _preferSpeechPeaks = true;
  bool _oneSegmentPerClip = false;
  bool _requireAllClips = false;

  List<MediaItem> get _audioItems =>
      widget.mediaLibrary.where((m) => m.type == MediaType.audio).toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ハイライト生成（高品質）'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMode(),
            const SizedBox(height: 12),
            _buildDuration(),
            const SizedBox(height: 12),
            _buildPattern(),
            const SizedBox(height: 12),
            _buildPreferences(),
            const SizedBox(height: 12),
            _buildBgm(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _canSubmit()
              ? () {
                  final request = HighlightGenerationRequest(
                    mode: _mode,
                    targetDuration: _duration,
                    pattern: _pattern,
                    preferences: HighlightPreferences(
                      preferHighMotion: _preferHighMotion,
                      preferFaces: _preferFaces,
                      preferSpeechPeaks: _preferSpeechPeaks,
                      oneSegmentPerClip: _oneSegmentPerClip,
                      requireAllClips: _requireAllClips,
                      minGapSeconds: _pattern.minGapSeconds,
                      diversityWeight: _pattern.diversityWeight,
                    ),
                    bgm: _mode == HighlightGenerationMode.beat ? _bgm : null,
                  );
                  Navigator.pop(context, request);
                }
              : null,
          child: const Text('生成'),
        ),
      ],
    );
  }

  bool _canSubmit() {
    if (_mode == HighlightGenerationMode.beat) {
      return _bgm != null && (_bgm?.filePath.isNotEmpty ?? false);
    }
    return true;
  }

  Widget _buildMode() {
    return DropdownButtonFormField<HighlightGenerationMode>(
      value: _mode,
      decoration: const InputDecoration(
        labelText: 'モード',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(
          value: HighlightGenerationMode.pattern,
          child: Text('Pattern（おすすめ）'),
        ),
        DropdownMenuItem(
          value: HighlightGenerationMode.time,
          child: Text('Time-based'),
        ),
        DropdownMenuItem(
          value: HighlightGenerationMode.beat,
          child: Text('Beat-based（BGM必要）'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _mode = value;
          if (_mode != HighlightGenerationMode.beat) {
            _bgm = null;
          } else if (_bgm == null && _audioItems.isNotEmpty) {
            _bgm = _audioItems.first;
          }
        });
      },
    );
  }

  Widget _buildDuration() {
    return DropdownButtonFormField<Duration>(
      value: _duration,
      decoration: const InputDecoration(
        labelText: '長さ',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: Duration(seconds: 30), child: Text('30秒')),
        DropdownMenuItem(value: Duration(seconds: 60), child: Text('60秒')),
        DropdownMenuItem(value: Duration(seconds: 90), child: Text('90秒')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _duration = value);
      },
    );
  }

  Widget _buildPattern() {
    return DropdownButtonFormField<HighlightPattern>(
      value: _pattern,
      decoration: const InputDecoration(
        labelText: 'パターン',
        border: OutlineInputBorder(),
      ),
      items: HighlightPattern.allPatterns
          .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _pattern = value);
      },
    );
  }

  Widget _buildPreferences() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('嗜好（重視ポイント）', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('動き（モーション）を重視'),
          value: _preferHighMotion,
          onChanged: (v) => setState(() => _preferHighMotion = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('顔を重視'),
          value: _preferFaces,
          onChanged: (v) => setState(() => _preferFaces = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('会話/発話を重視'),
          value: _preferSpeechPeaks,
          onChanged: (v) => setState(() => _preferSpeechPeaks = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('1クリップにつき1セグメント'),
          value: _oneSegmentPerClip,
          onChanged: (v) => setState(() => _oneSegmentPerClip = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('全クリップを最低1回使う'),
          value: _requireAllClips,
          onChanged: (v) => setState(() => _requireAllClips = v),
        ),
      ],
    );
  }

  Widget _buildBgm() {
    final enabled = _mode == HighlightGenerationMode.beat;
    return DropdownButtonFormField<MediaItem?>(
      value: enabled ? _bgm : null,
      decoration: InputDecoration(
        labelText: 'BGM（音声）',
        border: const OutlineInputBorder(),
        helperText: enabled ? null : 'Beat-based のときのみ使用',
      ),
      items: [
        const DropdownMenuItem<MediaItem?>(value: null, child: Text('なし')),
        ..._audioItems.map(
          (a) => DropdownMenuItem<MediaItem?>(value: a, child: Text(a.name)),
        ),
      ],
      onChanged: enabled ? (value) => setState(() => _bgm = value) : null,
    );
  }
}
