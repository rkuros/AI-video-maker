import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/transition_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';

/// Dialog for editing highlight clips
class HighlightEditorDialog extends ConsumerStatefulWidget {
  final String trackId;
  final List<Clip> highlightClips;

  const HighlightEditorDialog({
    super.key,
    required this.trackId,
    required this.highlightClips,
  });

  @override
  ConsumerState<HighlightEditorDialog> createState() =>
      _HighlightEditorDialogState();
}

class _HighlightEditorDialogState extends ConsumerState<HighlightEditorDialog> {
  late List<Clip> _clips;
  String? _selectedClipId;

  @override
  void initState() {
    super.initState();
    _clips = List.from(widget.highlightClips);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 24),
            Expanded(
              child: Row(
                children: [
                  // Clips list
                  Expanded(
                    flex: 2,
                    child: _buildClipsList(),
                  ),
                  const VerticalDivider(),
                  // Clip editor
                  Expanded(
                    flex: 3,
                    child: _buildClipEditor(),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, size: 28),
        const SizedBox(width: 12),
        const Text(
          'Highlight Clip Editor',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildClipsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Clips',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${_clips.length} clips, ${_formatTotalDuration()}',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _clips.length,
            onReorder: _onReorder,
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final clip = _clips[index];
              final isSelected = _selectedClipId == clip.id;

              return ReorderableDragStartListener(
                key: ValueKey(clip.id),
                index: index,
                child: _buildClipCard(clip, index, isSelected),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClipCard(Clip clip, int index, bool isSelected) {
    final mediaLibrary = ref.watch(mediaLibraryProvider);
    final mediaItem = mediaLibrary.firstWhere(
      (item) => item.id == clip.mediaItemId,
      orElse: () => MediaItem(
        filePath: '',
        name: 'Unknown',
        type: MediaType.video,
        duration: Duration.zero,
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? Colors.blue[900] : Colors.grey[850],
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedClipId = clip.id;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Drag handle
              Icon(Icons.drag_indicator, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 12),
              // Index
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaItem.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(clip.duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteClip(index),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipEditor() {
    if (_selectedClipId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.white38),
            SizedBox(height: 16),
            Text(
              'Select a clip to edit',
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    final clip = _clips.firstWhere((c) => c.id == _selectedClipId!);
    final mediaLibrary = ref.watch(mediaLibraryProvider);
    final mediaItem = mediaLibrary.firstWhere(
      (item) => item.id == clip.mediaItemId,
      orElse: () => MediaItem(
        filePath: '',
        name: 'Unknown',
        type: MediaType.video,
        duration: Duration.zero,
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Clip Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildSection('Basic Info', [
            _buildInfoRow('Name', mediaItem.name),
            _buildInfoRow('Duration', _formatDuration(clip.duration)),
            _buildInfoRow('Source', _formatDuration(clip.sourceStart)),
          ]),
          const SizedBox(height: 16),
          _buildSection('Timing', [
            _buildTimingControls(clip, mediaItem),
          ]),
          const SizedBox(height: 16),
          _buildSection('Audio', [
            _buildAudioControls(clip),
          ]),
          const SizedBox(height: 16),
          _buildSection('Transitions', [
            _buildTransitionControls(clip),
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
        const SizedBox(height: 12),
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
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingControls(Clip clip, MediaItem mediaItem) {
    final maxDuration = mediaItem.duration.inSeconds;
    final sourceStartSeconds = clip.sourceStart.inSeconds.toDouble();
    final sourceDurationSeconds = clip.sourceDuration.inSeconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Source Start: ${_formatDuration(clip.sourceStart)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        Slider(
          value: sourceStartSeconds,
          min: 0,
          max: (maxDuration - sourceDurationSeconds).clamp(0, maxDuration.toDouble()),
          divisions: maxDuration > 0 ? maxDuration : 1,
          onChanged: (value) {
            _updateClipSourceStart(clip, Duration(seconds: value.toInt()));
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Duration: ${_formatDuration(clip.sourceDuration)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        Slider(
          value: sourceDurationSeconds,
          min: 1,
          max: (maxDuration - sourceStartSeconds).clamp(1, maxDuration.toDouble()),
          divisions: maxDuration > 0 ? maxDuration : 1,
          onChanged: (value) {
            _updateClipSourceDuration(clip, Duration(seconds: value.toInt()));
          },
        ),
      ],
    );
  }

  Widget _buildAudioControls(Clip clip) {
    return Column(
      children: [
        Text(
          'Volume: ${(clip.volume * 100).toInt()}%',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
        Slider(
          value: clip.volume,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          onChanged: (value) {
            _updateClipVolume(clip, value);
          },
        ),
        SwitchListTile(
          title: const Text('Mute', style: TextStyle(fontSize: 12)),
          value: clip.isMuted,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            _updateClipMute(clip, value);
          },
        ),
      ],
    );
  }

  Widget _buildTransitionControls(Clip clip) {
    final hasInTransition = clip.inTransition != null;
    final hasOutTransition = clip.outTransition != null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTransitionButton(
                'Fade In',
                Icons.arrow_forward,
                hasInTransition,
                () => _toggleInTransition(clip),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTransitionButton(
                'Fade Out',
                Icons.arrow_back,
                hasOutTransition,
                () => _toggleOutTransition(clip),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransitionButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        isActive ? Icons.check_circle : Icons.circle_outlined,
        size: 16,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        backgroundColor: isActive ? Colors.green[700] : Colors.grey[800],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _applyChanges,
          icon: const Icon(Icons.check),
          label: const Text('Apply Changes'),
        ),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final clip = _clips.removeAt(oldIndex);
      _clips.insert(newIndex, clip);

      // Update clip start times based on new order
      Duration currentTime = Duration.zero;
      for (int i = 0; i < _clips.length; i++) {
        _clips[i] = _clips[i].copyWith(
          startTime: currentTime,
          endTime: currentTime + _clips[i].sourceDuration,
        );
        currentTime += _clips[i].sourceDuration;
      }
    });
  }

  void _deleteClip(int index) {
    setState(() {
      if (_clips[index].id == _selectedClipId) {
        _selectedClipId = null;
      }
      _clips.removeAt(index);

      // Update clip start times
      Duration currentTime = Duration.zero;
      for (int i = 0; i < _clips.length; i++) {
        _clips[i] = _clips[i].copyWith(
          startTime: currentTime,
          endTime: currentTime + _clips[i].sourceDuration,
        );
        currentTime += _clips[i].sourceDuration;
      }
    });
  }

  void _updateClipSourceStart(Clip clip, Duration newStart) {
    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        _clips[index] = _clips[index].copyWith(sourceStart: newStart);
      }
    });
  }

  void _updateClipSourceDuration(Clip clip, Duration newDuration) {
    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        final updatedClip = _clips[index].copyWith(
          sourceDuration: newDuration,
          endTime: _clips[index].startTime + newDuration,
        );
        _clips[index] = updatedClip;

        // Update subsequent clip start times
        Duration currentTime = updatedClip.endTime;
        for (int i = index + 1; i < _clips.length; i++) {
          _clips[i] = _clips[i].copyWith(
            startTime: currentTime,
            endTime: currentTime + _clips[i].sourceDuration,
          );
          currentTime += _clips[i].sourceDuration;
        }
      }
    });
  }

  void _updateClipVolume(Clip clip, double volume) {
    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        _clips[index] = _clips[index].copyWith(volume: volume);
      }
    });
  }

  void _updateClipMute(Clip clip, bool isMuted) {
    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        _clips[index] = _clips[index].copyWith(isMuted: isMuted);
      }
    });
  }

  void _toggleInTransition(Clip clip) {
    final transitionService = ref.read(transitionServiceProvider);

    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        if (_clips[index].inTransition != null) {
          _clips[index] = _clips[index].copyWith(inTransition: null);
        } else {
          final transition = transitionService.createFadeIn();
          _clips[index] = _clips[index].copyWith(inTransition: transition);
        }
      }
    });
  }

  void _toggleOutTransition(Clip clip) {
    final transitionService = ref.read(transitionServiceProvider);

    setState(() {
      final index = _clips.indexWhere((c) => c.id == clip.id);
      if (index != -1) {
        if (_clips[index].outTransition != null) {
          _clips[index] = _clips[index].copyWith(outTransition: null);
        } else {
          final transition = transitionService.createFadeOut();
          _clips[index] = _clips[index].copyWith(outTransition: transition);
        }
      }
    });
  }

  void _applyChanges() {
    // Remove old clips from timeline
    final timelineNotifier = ref.read(timelineProvider.notifier);
    for (final clip in widget.highlightClips) {
      timelineNotifier.removeClip(widget.trackId, clip.id);
    }

    // Add updated clips to timeline
    for (final clip in _clips) {
      timelineNotifier.addClip(widget.trackId, clip);
    }

    Navigator.pop(context, true);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatTotalDuration() {
    final totalDuration = _clips.fold<Duration>(
      Duration.zero,
      (sum, clip) => sum + clip.duration,
    );
    return _formatDuration(totalDuration);
  }
}
