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
  bool _showExpertMode = false;
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
    final isAutoMode =
        (autoDenoiseEffect?.parameters['autoMode'] as bool?) ?? false;

    // Get denoise settings
    final settings = autoDenoiseEffect != null
        ? DenoiseSettings.fromJson(autoDenoiseEffect.parameters)
        : oldDenoiseEffect != null
            ? DenoiseSettings.fromJson(oldDenoiseEffect.parameters)
            : const DenoiseSettings();

    final slowCpuFiltersEnabled = settings.backend == DenoiseBackend.ffmpeg &&
        (settings.useNlmeans ||
            settings.useBm3d ||
            settings.useVaguedenoiser ||
            settings.useDctdnoiz);

    DenoiseLevel coerceSimpleLevel(DenoiseLevel level) {
      switch (level) {
        case DenoiseLevel.fast:
        case DenoiseLevel.balanced:
        case DenoiseLevel.high:
          return level;
        case DenoiseLevel.maximum:
        case DenoiseLevel.aiEnhanced:
          return DenoiseLevel.high;
      }
    }

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
        // Enable/disable toggle at the top
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

                  // Auto-select optimal backend
                  final optimalBackend = Platform.isMacOS
                      ? DenoiseBackend.coreImage
                      : DenoiseBackend.ffmpeg;

                  final effect = AutoDenoiseEffect(
                    settings: settings.copyWith(backend: optimalBackend),
                    autoMode: false,
                  );
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

        const SizedBox(height: 12),

        // Auto Optimize (works even when Noise Reduction is off)
        ElevatedButton.icon(
          onPressed: _isAnalyzing || mediaItem == null
              ? null
              : () => _autoAnalyzeAndApply(
                    mediaItem!.filePath,
                    clip,
                    selectedTrackId,
                  ),
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
          'Analyze this clip and apply recommended noise reduction',
          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),

        if (!hasDenoising) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border.all(color: Colors.grey[700]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.noise_control_off, size: 40, color: Colors.grey[600]),
                const SizedBox(height: 12),
                Text(
                  'Noise Reduction is Off',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Turn it on, or just press Auto Optimize',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],

        if (hasDenoising) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Auto/Custom indicator
          Row(
            children: [
              Icon(
                isAutoMode ? Icons.auto_awesome : Icons.tune,
                size: 14,
                color: isAutoMode ? Colors.lightBlue[200] : Colors.grey[500],
              ),
              const SizedBox(width: 6),
              Text(
                isAutoMode ? 'Mode: Auto' : 'Mode: Custom',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Simple Mode - Quality Level Selector
          _buildLabel('Quality'),
          const SizedBox(height: 4),
          Text(
            'Choose processing quality (higher = better result, slower)',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),

          SegmentedButton<DenoiseLevel>(
            segments: [
              ButtonSegment(
                value: DenoiseLevel.fast,
                label: Text('Fast', style: TextStyle(fontSize: 11)),
                tooltip: 'Quick preview - suitable for real-time editing',
              ),
              ButtonSegment(
                value: DenoiseLevel.balanced,
                label: Text('Good', style: TextStyle(fontSize: 11)),
                tooltip: 'Balanced quality and speed - recommended',
              ),
              ButtonSegment(
                value: DenoiseLevel.high,
                label: Text('Best', style: TextStyle(fontSize: 11)),
                tooltip: 'High quality - may take longer to process',
              ),
            ],
            selected: {coerceSimpleLevel(settings.level)},
            onSelectionChanged: (Set<DenoiseLevel> selected) {
              final level = selected.first;
              applySettings((current) {
                // In the simple UI, quality maps to safe/fast presets.
                // Slow filters (nlmeans/bm3d) are only available in advanced settings.
                final preset = switch (level) {
                  DenoiseLevel.fast => (strength: 0.35, temporal: 2, luma: 0.55, chroma: 0.40),
                  DenoiseLevel.balanced => (strength: 0.55, temporal: 3, luma: 0.70, chroma: 0.55),
                  DenoiseLevel.high => (strength: 0.70, temporal: 4, luma: 0.85, chroma: 0.70),
                  _ => (strength: 0.55, temporal: 3, luma: 0.70, chroma: 0.55),
                };

                return current.copyWith(
                  level: level,
                  strength: preset.strength,
                  temporalRadius: preset.temporal,
                  lumaStrength: preset.luma,
                  chromaStrength: preset.chroma,
                  useNlmeans: slowCpuFiltersEnabled &&
                      level.index >= DenoiseLevel.balanced.index,
                  useBm3d:
                      slowCpuFiltersEnabled && level.index >= DenoiseLevel.high.index,
                  useVaguedenoiser: false,
                  useDctdnoiz: false,
                );
              });
            },
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(TextStyle(fontSize: 11)),
            ),
          ),

          const SizedBox(height: 8),

          // Processing time indicator
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                'Processing time: ${settings.level.estimatedTime}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Preserve details toggle (simple, high-impact)
          SwitchListTile(
            title: const Text('Preserve Details', style: TextStyle(fontSize: 12)),
            subtitle: const Text('Helps avoid over-smoothing', style: TextStyle(fontSize: 10)),
            value: settings.preserveDetails,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              applySettings((current) => current.copyWith(preserveDetails: value));
            },
          ),

          const SizedBox(height: 8),

          // Master Strength Slider
          _buildLabel('Strength: ${(settings.strength * 100).toInt()}%'),
          const SizedBox(height: 4),
          Text(
            'Adjust overall noise reduction intensity',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
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

          // Advanced settings toggle
          InkWell(
            onTap: () {
              setState(() {
                _showExpertMode = !_showExpertMode;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _showExpertMode ? Colors.orange[900]?.withOpacity(0.3) : Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _showExpertMode ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: _showExpertMode ? Colors.orange[300] : Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showExpertMode ? 'Hide Advanced Settings' : 'Show Advanced Settings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _showExpertMode ? Colors.orange[300] : Colors.grey[300],
                      ),
                    ),
                  ),
                  if (_showExpertMode)
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: Colors.orange[300],
                    ),
                ],
              ),
            ),
          ),

          if (_showExpertMode) ...[
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[900]?.withOpacity(0.1),
                border: Border.all(color: Colors.orange[900]!, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange[300]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Advanced controls - change only if needed',
                      style: TextStyle(fontSize: 10, color: Colors.orange[200]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Backend selection
            _buildLabel('Processing Backend'),
            const SizedBox(height: 4),
            Text(
              Platform.isMacOS
                  ? 'GPU backends are faster on Mac'
                  : 'FFmpeg CPU backend is recommended',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<DenoiseBackend>(
              value: settings.backend,
              items: [
                const DropdownMenuItem(
                  value: DenoiseBackend.ffmpeg,
                  child: Text('FFmpeg (CPU)', style: TextStyle(fontSize: 12)),
                ),
                if (Platform.isMacOS)
                  const DropdownMenuItem(
                    value: DenoiseBackend.coreImage,
                    child: Text('Core Image (GPU)', style: TextStyle(fontSize: 12)),
                  ),
                if (Platform.isMacOS)
                  const DropdownMenuItem(
                    value: DenoiseBackend.coreML,
                    child: Text('Core ML (NPU/GPU)', style: TextStyle(fontSize: 12)),
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),

            if (settings.backend == DenoiseBackend.ffmpeg) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text(
                  'Slow CPU Filters (nlmeans/bm3d)',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: const Text(
                  'Very slow. In simple mode, “Good/Best” will auto-check them when enabled.',
                  style: TextStyle(fontSize: 10),
                ),
                value: slowCpuFiltersEnabled,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  if (!value) {
                    applySettings(
                      (current) => current.copyWith(
                        useNlmeans: false,
                        useBm3d: false,
                        useVaguedenoiser: false,
                        useDctdnoiz: false,
                      ),
                    );
                    return;
                  }

                  applySettings(
                    (current) => current.copyWith(
                      useNlmeans: current.level.index >= DenoiseLevel.balanced.index,
                      useBm3d: current.level.index >= DenoiseLevel.high.index,
                      useVaguedenoiser: false,
                      useDctdnoiz: false,
                    ),
                  );
                },
              ),
              Text(
                'Tip: These are typically export-only due to processing time.',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],

            if (Platform.isMacOS && settings.backend == DenoiseBackend.coreML) ...[
              const SizedBox(height: 12),
              _buildLabel('Core ML Model File'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      settings.aiModelPath?.isNotEmpty == true
                          ? settings.aiModelPath!.split('/').last
                          : 'No model selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: settings.aiModelPath?.isNotEmpty == true
                            ? Colors.white
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
                    child: const Text('Browse', style: TextStyle(fontSize: 11)),
                  ),
                  if (settings.aiModelPath?.isNotEmpty == true)
                    TextButton(
                      onPressed: () {
                        applySettings(
                          (current) => current.copyWith(
                            aiModelPath: null,
                            backend: Platform.isMacOS ? DenoiseBackend.coreImage : DenoiseBackend.ffmpeg,
                            useAiModel: false,
                          ),
                        );
                      },
                      child: const Text('Clear', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Fine-tuning parameters
            _buildLabel('Fine-Tuning Parameters'),
            const SizedBox(height: 12),

            _buildLabel('Temporal Radius: ${settings.temporalRadius} frames'),
            Text(
              'Number of frames to analyze for temporal noise reduction',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
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

            _buildLabel('Luma (Brightness) Strength: ${(settings.lumaStrength * 100).toInt()}%'),
            Text(
              'Noise reduction strength for brightness channel',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
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

            _buildLabel('Chroma (Color) Strength: ${(settings.chromaStrength * 100).toInt()}%'),
            Text(
              'Noise reduction strength for color channels',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
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

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Individual Filter Toggles
            _buildLabel('Extra Filters (CPU only)'),
            Text(
              settings.backend == DenoiseBackend.ffmpeg
                  ? 'Enable/disable specific denoising algorithms (very slow)'
                  : 'These filters are ignored on GPU/NPU backends. Switch to FFmpeg (CPU) to use them.',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            if (settings.backend == DenoiseBackend.ffmpeg) ...[
              CheckboxListTile(
                title: const Text('Non-local Means (nlmeans)', style: TextStyle(fontSize: 12)),
                subtitle: const Text('Detail-preserving spatial denoise', style: TextStyle(fontSize: 10)),
                value: settings.useNlmeans,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  applySettings((current) => current.copyWith(useNlmeans: value));
                },
              ),
              CheckboxListTile(
                title: const Text('Block-Matching 3D (bm3d)', style: TextStyle(fontSize: 12)),
                subtitle: const Text('Highest quality, slower processing', style: TextStyle(fontSize: 10)),
                value: settings.useBm3d,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  applySettings((current) => current.copyWith(useBm3d: value));
                },
              ),
              CheckboxListTile(
                title: const Text('Vague Denoiser', style: TextStyle(fontSize: 12)),
                subtitle: const Text('Removes fine grain and texture noise', style: TextStyle(fontSize: 10)),
                value: settings.useVaguedenoiser,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  applySettings((current) => current.copyWith(useVaguedenoiser: value));
                },
              ),
            ],
          ],
        ],
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

      // Keep backend stable (or pick a sensible default when enabling via Auto Optimize).
      final existingEffect = _findEffectByType(clip, 'auto_denoise') ??
          _findEffectByType(clip, 'low_light_denoise');
      final existingSettings = existingEffect == null
          ? null
          : DenoiseSettings.fromJson(existingEffect.parameters);
      final preferredBackend = existingSettings?.backend ??
          (Platform.isMacOS ? DenoiseBackend.coreImage : DenoiseBackend.ffmpeg);
      final preferredModelPath = existingSettings?.aiModelPath;
      final backend = preferredBackend == DenoiseBackend.coreML &&
              (preferredModelPath == null || preferredModelPath.isEmpty)
          ? (Platform.isMacOS ? DenoiseBackend.coreImage : DenoiseBackend.ffmpeg)
          : preferredBackend;

      final mergedSettings = recommendedSettings.copyWith(
        backend: backend,
        useAiModel: backend == DenoiseBackend.coreML,
        aiModelPath: backend == DenoiseBackend.coreML ? preferredModelPath : null,
      );

      // Apply auto denoise effect
      final effect = AutoDenoiseEffect(
        settings: mergedSettings,
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
