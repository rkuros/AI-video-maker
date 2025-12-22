import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/transition_provider.dart';
import 'package:video_editor/core/logic/audio_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/preview_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/models/denoise_level.dart';
import 'package:video_editor/core/services/video_analysis_service.dart';

/// Properties panel for editing selected items
enum _EffectPreset {
  colorAdjustment,
  filterSepia,
  filterMonochrome,
  filterVintage,
}

class PropertiesPanel extends ConsumerStatefulWidget {
  final String? selectedClipId;
  final String? selectedTrackId;

  const PropertiesPanel({
    super.key,
    this.selectedClipId,
    this.selectedTrackId,
  });

  @override
  ConsumerState<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends ConsumerState<PropertiesPanel> {
  _EffectPreset _selectedEffectPreset = _EffectPreset.colorAdjustment;
  bool _isAnalyzing = false;
  bool _showAdvancedSettings = false;
  final _analysisService = VideoAnalysisService();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: widget.selectedClipId != null
                ? _buildClipProperties()
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  void _updateSelectedClip(Clip updatedClip) {
    if (widget.selectedClipId == null || widget.selectedTrackId == null) {
      return;
    }
    ref
        .read(timelineProvider.notifier)
        .updateClip(widget.selectedTrackId!, updatedClip);
  }

  Effect? _findEffectByType(Clip clip, String type) {
    for (final effect in clip.effects) {
      if (effect.type == type) return effect;
    }
    return null;
  }

  void _addEffect(Clip clip, _EffectPreset preset) {
    Effect effect;
    switch (preset) {
      case _EffectPreset.colorAdjustment:
        effect = ColorAdjustmentEffect();
        break;
      case _EffectPreset.filterSepia:
        effect = FilterEffect(filterType: 'Sepia', intensity: 1.0);
        break;
      case _EffectPreset.filterMonochrome:
        effect = FilterEffect(filterType: 'Monochrome', intensity: 1.0);
        break;
      case _EffectPreset.filterVintage:
        effect = FilterEffect(filterType: 'Vintage', intensity: 1.0);
        break;
    }

    _updateSelectedClip(clip.addEffect(effect));
  }

  void _removeEffect(Clip clip, String effectId) {
    _updateSelectedClip(clip.removeEffect(effectId));
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          const Text(
            'Properties',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.selectedClipId != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                ref.read(selectionProvider.notifier).clearSelection();
              },
              tooltip: 'Clear Selection',
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: Colors.white38,
          ),
          SizedBox(height: 16),
          Text(
            'No selection',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Select a clip to view properties',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClipProperties() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSection('Basic Info', [
            _buildInfoRow('Clip ID', widget.selectedClipId ?? 'N/A'),
          ]),
          const SizedBox(height: 16),
          _buildSection('Audio', [
            _buildAudioSettings(),
          ]),
          const SizedBox(height: 16),
          _buildSection('Transitions', [
            _buildTransitionSettings(),
          ]),
          const SizedBox(height: 16),
          _buildSection('Effects', [
            _buildEffectsPlaceholder(),
          ]),
          const SizedBox(height: 16),
          _buildSection('Noise Reduction', [
            _buildNoiseReductionSettings(),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionSettings() {
    final settings = ref.watch(transitionSettingsProvider);
    final operations = ref.read(transitionOperationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Transition type selector
        _buildLabel('Type'),
        DropdownButtonFormField<TransitionType>(
          initialValue: settings.type,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: TransitionType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(
                _getTransitionName(type),
                style: const TextStyle(fontSize: 12),
              ),
            );
          }).toList(),
          onChanged: (type) {
            if (type != null) {
              ref.read(transitionSettingsProvider.notifier).setType(type);
            }
          },
        ),
        const SizedBox(height: 12),

        // Duration slider
        _buildLabel('Duration: ${_formatDuration(settings.duration)}'),
        Slider(
          value: settings.duration.inMilliseconds.toDouble(),
          min: 100,
          max: 5000,
          divisions: 49,
          onChanged: (value) {
            ref
                .read(transitionSettingsProvider.notifier)
                .setDuration(Duration(milliseconds: value.toInt()));
          },
        ),
        const SizedBox(height: 12),

        // Direction selector for wipe/slide
        if (settings.type == TransitionType.wipe ||
            settings.type == TransitionType.slide) ...[
          _buildLabel('Direction'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'left', label: Text('Left')),
              ButtonSegment(value: 'right', label: Text('Right')),
              ButtonSegment(value: 'up', label: Text('Up')),
              ButtonSegment(value: 'down', label: Text('Down')),
            ],
            selected: {settings.parameters['direction'] as String? ?? 'left'},
            onSelectionChanged: (Set<String> selected) {
              ref
                  .read(transitionSettingsProvider.notifier)
                  .setParameter('direction', selected.first);
            },
          ),
          const SizedBox(height: 12),
        ],

        // Zoom type selector
        if (settings.type == TransitionType.zoom) ...[
          _buildLabel('Zoom Type'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in', label: Text('In')),
              ButtonSegment(value: 'out', label: Text('Out')),
            ],
            selected: {settings.parameters['zoomType'] as String? ?? 'in'},
            onSelectionChanged: (Set<String> selected) {
              ref
                  .read(transitionSettingsProvider.notifier)
                  .setParameter('zoomType', selected.first);
            },
          ),
          const SizedBox(height: 12),
        ],

        // Apply buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.selectedClipId != null &&
                        widget.selectedTrackId != null
                    ? () {
                        operations.applyInTransition(
                          widget.selectedTrackId!,
                          widget.selectedClipId!,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('In-transition applied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('In', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.selectedClipId != null &&
                        widget.selectedTrackId != null
                    ? () {
                        operations.applyOutTransition(
                          widget.selectedTrackId!,
                          widget.selectedClipId!,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Out-transition applied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Out', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioSettings() {
    final timeline = ref.watch(timelineProvider);
    final audioOps = ref.read(audioOperationsProvider);
    final audioService = ref.read(audioServiceProvider);

    if (widget.selectedClipId == null) {
      return const Text(
        'Select a clip to adjust audio',
        style: TextStyle(fontSize: 12, color: Colors.white54),
      );
    }

    final clip = timeline.findClip(widget.selectedClipId!);
    if (clip == null) {
      return const Text(
        'Clip not found',
        style: TextStyle(fontSize: 12, color: Colors.white54),
      );
    }

    final hasFadeIn = audioService.hasFadeIn(clip);
    final hasFadeOut = audioService.hasFadeOut(clip);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Volume slider
        _buildLabel('Volume: ${(clip.volume * 100).toInt()}%'),
        Slider(
          value: clip.volume,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          onChanged: (value) {
            audioOps.setClipVolume(
              widget.selectedTrackId!,
              widget.selectedClipId!,
              value,
            );
          },
        ),
        const SizedBox(height: 8),

        // Mute button
        SwitchListTile(
          title: const Text('Mute', style: TextStyle(fontSize: 12)),
          value: clip.isMuted,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            audioOps.toggleClipMute(
              widget.selectedTrackId!,
              widget.selectedClipId!,
            );
          },
        ),
        const SizedBox(height: 12),

        // Fade controls
        _buildLabel('Fade Effects'),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (hasFadeIn) {
                    audioOps.removeFadeIn(
                      widget.selectedTrackId!,
                      widget.selectedClipId!,
                    );
                  } else {
                    audioOps.addFadeIn(
                      widget.selectedTrackId!,
                      widget.selectedClipId!,
                      const Duration(seconds: 1),
                    );
                  }
                },
                icon: Icon(
                  hasFadeIn ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                ),
                label: const Text('Fade In', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  backgroundColor:
                      hasFadeIn ? Colors.green[700] : Colors.grey[800],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (hasFadeOut) {
                    audioOps.removeFadeOut(
                      widget.selectedTrackId!,
                      widget.selectedClipId!,
                    );
                  } else {
                    audioOps.addFadeOut(
                      widget.selectedTrackId!,
                      widget.selectedClipId!,
                      const Duration(seconds: 1),
                    );
                  }
                },
                icon: Icon(
                  hasFadeOut ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                ),
                label: const Text('Fade Out', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  backgroundColor:
                      hasFadeOut ? Colors.green[700] : Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEffectsPlaceholder() {
    final timeline = ref.watch(timelineProvider);
    final clip = timeline.findClip(widget.selectedClipId!);
    final previewState = ref.watch(previewProvider);

    if (clip == null) {
      return const Text('No clip selected');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Add effect controls
        _buildLabel('Add Effect'),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<_EffectPreset>(
                key: ValueKey(_selectedEffectPreset),
                initialValue: _selectedEffectPreset,
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: _EffectPreset.values.map((preset) {
                  return DropdownMenuItem(
                    value: preset,
                    child: Text(
                      _effectPresetLabel(preset),
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (preset) {
                  if (preset == null) return;
                  setState(() {
                    _selectedEffectPreset = preset;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _addEffect(clip, _selectedEffectPreset),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Effect count display
        _buildLabel('Applied Effects: ${clip.effects.length}'),
        const SizedBox(height: 8),

        // List of applied effects
        if (clip.effects.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[700]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Icon(Icons.auto_fix_high, size: 32, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'No effects applied',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
        else
          ...clip.effects.map((effect) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.auto_fix_high, size: 20),
                  title: Text(effect.name, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(effect.type, style: const TextStyle(fontSize: 10)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () => _removeEffect(clip, effect.id),
                    tooltip: 'Remove',
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              )),

        const SizedBox(height: 16),

        // Effect preview buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: clip.effects.isEmpty || previewState.isLoading
                    ? null
                    : () {
                        if (previewState.isEffectPreview) {
                          ref.read(previewProvider.notifier).exitEffectPreview();
                        } else {
                          final mediaLibrary = ref.read(mediaLibraryProvider);
                          final mediaItem = mediaLibrary.firstWhere(
                            (m) => m.id == clip.mediaItemId,
                            orElse: () => MediaItem(
                              filePath: '',
                              name: 'Unknown',
                              type: MediaType.video,
                              duration: Duration.zero,
                            ),
                          );
                          ref.read(previewProvider.notifier).generateEffectPreview(clip, mediaItem);
                        }
                      },
                icon: Icon(
                  previewState.isEffectPreview ? Icons.close : Icons.visibility,
                  size: 16,
                ),
                label: Text(
                  previewState.isEffectPreview ? 'Exit Preview' : 'Preview Effects',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),

        if (previewState.isLoading && !previewState.isPlaying)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildNoiseReductionSettings() {
    final timeline = ref.watch(timelineProvider);
    final mediaLibrary = ref.watch(mediaLibraryProvider);
    final clip = timeline.findClip(widget.selectedClipId!);
    final selectedTrackId = widget.selectedTrackId;

    if (clip == null) {
      return const Text('No clip selected');
    }

    // Check if auto denoise effect is applied
    final autoDenoiseEffect = _findEffectByType(clip, 'auto_denoise');
    final oldDenoiseEffect = _findEffectByType(clip, 'low_light_denoise');
    final hasDenoising = autoDenoiseEffect != null || oldDenoiseEffect != null;

    // Get denoise settings
    final settings = autoDenoiseEffect != null
        ? DenoiseSettings.fromJson(autoDenoiseEffect.parameters)
        : oldDenoiseEffect != null
            ? DenoiseSettings.fromJson(oldDenoiseEffect.parameters)
            : const DenoiseSettings();

    void applySettings(DenoiseSettings Function(DenoiseSettings current) update) {
      if (selectedTrackId == null) return;
      final currentTimeline = ref.read(timelineProvider);
      final currentClip = currentTimeline.findClip(widget.selectedClipId!);
      if (currentClip == null) return;

      final currentEffect = _findEffectByType(currentClip, 'auto_denoise') ??
          _findEffectByType(currentClip, 'low_light_denoise');
      if (currentEffect == null) return;

      final currentSettings = DenoiseSettings.fromJson(currentEffect.parameters);
      final updatedEffect = AutoDenoiseEffect(
        id: currentEffect.id,
        settings: update(currentSettings),
        autoMode: false,
      );
      _updateSelectedClip(currentClip.updateEffect(updatedEffect));
    }

    // Get media item for analysis
    MediaItem? mediaItem;
    try {
      mediaItem = mediaLibrary.firstWhere(
        (item) => item.id == clip.mediaItemId,
      );
    } catch (e) {
      // Media item not found
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Auto Analyze Button (prominent)
        ElevatedButton.icon(
          onPressed: _isAnalyzing || mediaItem == null
              ? null
              : () => _autoAnalyzeAndApply(mediaItem!.filePath, clip, selectedTrackId),
          icon: _isAnalyzing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_isAnalyzing ? 'Analyzing...' : 'Auto Optimize'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Automatically analyze and apply optimal noise reduction',
          style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // Enable/disable toggle
        Row(
          children: [
            Expanded(
              child: Text(
                'Noise Reduction',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            Switch(
              value: hasDenoising,
              onChanged: (value) {
                if (selectedTrackId == null) return;
                if (value && !hasDenoising) {
                  // Remove any existing denoise effects before adding new one
                  var updatedClip = clip;
                  final existingAuto = _findEffectByType(clip, 'auto_denoise');
                  final existingManual = _findEffectByType(clip, 'low_light_denoise');

                  if (existingAuto != null) {
                    updatedClip = updatedClip.removeEffect(existingAuto.id);
                  }
                  if (existingManual != null) {
                    updatedClip = updatedClip.removeEffect(existingManual.id);
                  }

                  final effect = AutoDenoiseEffect(settings: settings, autoMode: false);
                  _updateSelectedClip(updatedClip.addEffect(effect));
                } else if (!value) {
                  if (autoDenoiseEffect != null) {
                    _updateSelectedClip(clip.removeEffect(autoDenoiseEffect.id));
                  } else if (oldDenoiseEffect != null) {
                    _updateSelectedClip(clip.removeEffect(oldDenoiseEffect.id));
                  }
                }
              },
            ),
          ],
        ),

        if (hasDenoising) ...[
          const SizedBox(height: 16),

          // Denoise Level Selector
          _buildLabel('Quality Level (${settings.level.estimatedTime})'),
          const SizedBox(height: 8),

          SegmentedButton<DenoiseLevel>(
            segments: [
              ButtonSegment(
                value: DenoiseLevel.fast,
                label: Text('Fast', style: TextStyle(fontSize: 11)),
                tooltip: DenoiseLevel.fast.description,
              ),
              ButtonSegment(
                value: DenoiseLevel.balanced,
                label: Text('Balanced', style: TextStyle(fontSize: 11)),
                tooltip: DenoiseLevel.balanced.description,
              ),
              ButtonSegment(
                value: DenoiseLevel.high,
                label: Text('High', style: TextStyle(fontSize: 11)),
                tooltip: DenoiseLevel.high.description,
              ),
            ],
            selected: {settings.level},
            onSelectionChanged: (Set<DenoiseLevel> selected) {
              final level = selected.first;
              applySettings((current) => current.copyWith(
                level: level,
                useNlmeans: level.index >= DenoiseLevel.balanced.index,
                useBm3d: level.index >= DenoiseLevel.high.index,
                useVaguedenoiser: level == DenoiseLevel.maximum,
              ));
            },
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(TextStyle(fontSize: 11)),
            ),
          ),

          const SizedBox(height: 16),

          _buildLabel('Backend'),
          const SizedBox(height: 8),
          DropdownButtonFormField<DenoiseBackend>(
            value: settings.backend,
            items: [
              const DropdownMenuItem(
                value: DenoiseBackend.ffmpeg,
                child: Text('FFmpeg (CPU)'),
              ),
              if (Platform.isMacOS)
                const DropdownMenuItem(
                  value: DenoiseBackend.coreImage,
                  child: Text('Core Image (GPU)'),
                ),
              if (Platform.isMacOS)
                const DropdownMenuItem(
                  value: DenoiseBackend.coreML,
                  child: Text('Core ML (NPU/GPU)'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              applySettings(
                (current) => current.copyWith(
                  backend: value,
                  useAiModel: value == DenoiseBackend.coreML,
                  aiModelPath: value == DenoiseBackend.coreML
                      ? current.aiModelPath
                      : null,
                ),
              );
            },
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),

          if (Platform.isMacOS && settings.backend == DenoiseBackend.coreImage) ...[
            const SizedBox(height: 8),
            Text(
              'Core Image uses GPU for spatial denoise. Temporal denoise is still applied via FFmpeg (hqdn3d).',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],

          if (Platform.isMacOS && settings.backend == DenoiseBackend.coreML) ...[
            const SizedBox(height: 12),
            _buildLabel('Core ML Model'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    settings.aiModelPath?.isNotEmpty == true
                        ? settings.aiModelPath!
                        : 'No model selected',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: settings.aiModelPath?.isNotEmpty == true
                          ? Colors.grey[800]
                          : Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final picked = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['mlmodel', 'mlpackage', 'mlmodelc'],
                    );
                    final path = picked?.files.single.path;
                    if (path == null) return;
                    applySettings((current) => current.copyWith(aiModelPath: path));
                  },
                  child: const Text('Choose'),
                ),
                if (settings.aiModelPath?.isNotEmpty == true)
                  TextButton(
                    onPressed: () {
                      applySettings(
                        (current) => current.copyWith(
                          aiModelPath: null,
                          backend: DenoiseBackend.ffmpeg,
                          useAiModel: false,
                        ),
                      );
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Core ML denoise runs as an offline pre-render step (export & effect preview). Timeline real-time preview falls back to FFmpeg/Core Image.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],

          // Master Strength Slider
          _buildLabel('Strength: ${(settings.strength * 100).toInt()}%'),
          Slider(
            value: settings.strength,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: '${(settings.strength * 100).toInt()}%',
            onChanged: (value) {
              applySettings((current) => current.copyWith(strength: value));
            },
          ),

          const SizedBox(height: 16),

          // Advanced Settings (collapsible)
          InkWell(
            onTap: () {
              setState(() {
                _showAdvancedSettings = !_showAdvancedSettings;
              });
            },
            child: Row(
              children: [
                Icon(
                  _showAdvancedSettings ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Advanced Settings',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          if (_showAdvancedSettings) ...[
            const SizedBox(height: 16),

            _buildLabel('Temporal Radius: ${settings.temporalRadius} frames'),
            Slider(
              value: settings.temporalRadius.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${settings.temporalRadius}',
              onChanged: (value) {
                applySettings(
                  (current) => current.copyWith(temporalRadius: value.round()),
                );
              },
            ),

            const SizedBox(height: 12),

            _buildLabel('Luma Strength: ${(settings.lumaStrength * 100).toInt()}%'),
            Slider(
              value: settings.lumaStrength,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(settings.lumaStrength * 100).toInt()}%',
              onChanged: (value) {
                applySettings((current) => current.copyWith(lumaStrength: value));
              },
            ),

            const SizedBox(height: 12),

            _buildLabel('Chroma Strength: ${(settings.chromaStrength * 100).toInt()}%'),
            Slider(
              value: settings.chromaStrength,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(settings.chromaStrength * 100).toInt()}%',
              onChanged: (value) {
                applySettings((current) => current.copyWith(chromaStrength: value));
              },
            ),

            const SizedBox(height: 12),

            // Individual Filter Toggles
            _buildLabel('Active Filters'),
            CheckboxListTile(
              title: const Text('nlmeans (Detail Preserving)', style: TextStyle(fontSize: 11)),
              value: settings.useNlmeans,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                applySettings((current) => current.copyWith(useNlmeans: value));
              },
            ),
            CheckboxListTile(
              title: const Text('bm3d (Highest Quality)', style: TextStyle(fontSize: 11)),
              value: settings.useBm3d,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                applySettings((current) => current.copyWith(useBm3d: value));
              },
            ),
            CheckboxListTile(
              title: const Text('vaguedenoiser (Fine Noise)', style: TextStyle(fontSize: 11)),
              value: settings.useVaguedenoiser,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                applySettings((current) => current.copyWith(useVaguedenoiser: value));
              },
            ),
          ],
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[700]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Icon(Icons.noise_control_off, size: 32, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'Noise reduction is off',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use Auto Optimize or toggle on',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _autoAnalyzeAndApply(
    String filePath,
    Clip clip,
    String? trackId,
  ) async {
    if (trackId == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // Analyze video
      final analysis = await _analysisService.analyzeVideo(filePath);

      // Get recommended settings
      final recommendedSettings = _analysisService.recommendSettings(analysis);

      // Apply auto denoise effect
      final effect = AutoDenoiseEffect(
        settings: recommendedSettings,
        autoMode: true,
      );

      // Remove old denoise effects if any
      var updatedClip = clip;
      final oldAuto = _findEffectByType(clip, 'auto_denoise');
      final oldManual = _findEffectByType(clip, 'low_light_denoise');

      if (oldAuto != null) {
        updatedClip = updatedClip.removeEffect(oldAuto.id);
      }
      if (oldManual != null) {
        updatedClip = updatedClip.removeEffect(oldManual.id);
      }

      // Add new effect
      updatedClip = updatedClip.addEffect(effect);
      _updateSelectedClip(updatedClip);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Applied ${recommendedSettings.level.displayName} denoise '
              '(Brightness: ${(analysis.averageBrightness * 100).toInt()}%, '
              'Noise: ${(analysis.noiseLevel * 100).toInt()}%)',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  String _getTransitionName(TransitionType type) {
    switch (type) {
      case TransitionType.fadeIn:
        return 'Fade In';
      case TransitionType.fadeOut:
        return 'Fade Out';
      case TransitionType.crossFade:
        return 'Cross Fade';
      case TransitionType.wipe:
        return 'Wipe';
      case TransitionType.slide:
        return 'Slide';
      case TransitionType.zoom:
        return 'Zoom';
    }
  }

  String _effectPresetLabel(_EffectPreset preset) {
    switch (preset) {
      case _EffectPreset.colorAdjustment:
        return 'Color Adjustment';
      case _EffectPreset.filterSepia:
        return 'Filter: Sepia';
      case _EffectPreset.filterMonochrome:
        return 'Filter: Monochrome';
      case _EffectPreset.filterVintage:
        return 'Filter: Vintage';
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
}
