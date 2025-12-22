import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:video_editor/core/logic/preview_provider.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/ui/dialogs/preview_loading_dialog.dart';

/// Preview panel widget for video playback
class PreviewPanel extends ConsumerWidget {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewState = ref.watch(previewProvider);

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Video display area
          Expanded(
            child: _buildVideoDisplay(context, previewState),
          ),
          // Playback controls
          _buildPlaybackControls(context, ref, previewState),
        ],
      ),
    );
  }

  Widget _buildVideoDisplay(BuildContext context, PreviewState state) {
    if (state.error != null) {
      return _buildErrorDisplay(state.error!);
    }

    if (state.isLoading) {
      return _buildLoadingDisplay();
    }

    if (state.controller == null || !state.controller!.value.isInitialized) {
      return _buildEmptyDisplay();
    }

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: state.controller!.value.aspectRatio,
            child: VideoPlayer(state.controller!),
          ),
        ),
        // Effect preview badge
        if (state.isEffectPreview)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Effect Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyDisplay() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 64,
            color: Colors.white54,
          ),
          SizedBox(height: 16),
          Text(
            'No video loaded',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Select a video from the media library',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingDisplay() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading video...',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorDisplay(String error) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  color: Colors.red[300],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    WidgetRef ref,
    PreviewState state,
  ) {
    final hasVideo =
        state.controller != null && state.controller!.value.isInitialized;

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          _buildProgressBar(ref, state),
          const SizedBox(height: 8),
          // Control buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    state.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: hasVideo ? Colors.white : Colors.grey,
                  ),
                  onPressed: hasVideo ? () => _handlePlayPause(context, ref) : null,
                  tooltip: state.isPlaying ? 'Pause' : 'Play',
                  iconSize: 32,
                ),
                const SizedBox(width: 16),
                // Stop button
                IconButton(
                  icon: Icon(
                    Icons.stop,
                    color: hasVideo ? Colors.white : Colors.grey,
                  ),
                  onPressed: hasVideo
                      ? () async {
                          await ref.read(previewProvider.notifier).pause();
                          await ref
                              .read(previewProvider.notifier)
                              .seekTo(Duration.zero);
                        }
                      : null,
                  tooltip: 'Stop',
                ),
                const SizedBox(width: 8),
                // Preview quality preset
                _buildPreviewQualitySelector(context, ref, state, hasVideo),
                const SizedBox(width: 32),
                // Time display
                Text(
                  _formatDuration(state.currentPosition),
                  style: TextStyle(
                    color: hasVideo ? Colors.white : Colors.grey,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ' / ',
                  style: TextStyle(
                    color: hasVideo ? Colors.grey : Colors.grey[700],
                  ),
                ),
                Text(
                  _formatDuration(state.duration),
                  style: TextStyle(
                    color: hasVideo ? Colors.white : Colors.grey,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 32),
                // Playback speed selector
                _buildSpeedSelector(ref, state, hasVideo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewQualitySelector(
    BuildContext context,
    WidgetRef ref,
    PreviewState state,
    bool enabled,
  ) {
    return PopupMenuButton<PreviewQualityPreset>(
      enabled: enabled,
      tooltip: 'Preview Quality',
      initialValue: state.timelinePreviewPreset,
      onSelected: (preset) {
        ref.read(previewProvider.notifier).setTimelinePreviewPreset(preset);
      },
      itemBuilder: (context) => PreviewQualityPreset.values
          .map(
            (preset) => PopupMenuItem(
              value: preset,
              child: Row(
                children: [
                  if (preset == state.timelinePreviewPreset)
                    const Icon(Icons.check, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(preset.label),
                ],
              ),
            ),
          )
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.high_quality, color: enabled ? Colors.white : Colors.grey),
          const SizedBox(width: 6),
          Text(
            state.timelinePreviewPreset.label,
            style: TextStyle(color: enabled ? Colors.white : Colors.grey),
          ),
          Icon(
            Icons.arrow_drop_down,
            color: enabled ? Colors.white : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(WidgetRef ref, PreviewState state) {
    final hasVideo =
        state.controller != null && state.controller!.value.isInitialized;
    final progress = hasVideo && state.duration.inMilliseconds > 0
        ? state.currentPosition.inMilliseconds / state.duration.inMilliseconds
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: hasVideo
              ? (details) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  final tapPosition =
                      (details.localPosition.dx / width).clamp(0.0, 1.0);
                  final seekMillis =
                      (state.duration.inMilliseconds * tapPosition).round();
                  ref
                      .read(previewProvider.notifier)
                      .seekTo(Duration(milliseconds: seekMillis));
                }
              : null,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedSelector(WidgetRef ref, PreviewState state, bool enabled) {
    return PopupMenuButton<PlaybackSpeed>(
      enabled: enabled,
      tooltip: 'Playback Speed',
      icon: Icon(
        Icons.speed,
        color: enabled ? Colors.white : Colors.grey,
      ),
      initialValue: state.speed,
      onSelected: (speed) {
        ref.read(previewProvider.notifier).setPlaybackSpeed(speed);
      },
      itemBuilder: (context) => PlaybackSpeed.values
          .map(
            (speed) => PopupMenuItem(
              value: speed,
              child: Row(
                children: [
                  if (speed == state.speed)
                    const Icon(Icons.check, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(speed.label),
                ],
              ),
            ),
          )
          .toList(),
    );
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

  void _handlePlayPause(BuildContext context, WidgetRef ref) {
    final previewState = ref.read(previewProvider);
    final previewNotifier = ref.read(previewProvider.notifier);
    final timeline = ref.read(timelineProvider);
    final mediaLibrary = ref.read(mediaLibraryProvider);

    // Check if we need to regenerate timeline preview
    if (timeline.tracks.isNotEmpty &&
        timeline.duration != Duration.zero &&
        (previewState.timelinePreviewPath == null ||
         previewState.currentVideoPath != previewState.timelinePreviewPath)) {
      // Show loading dialog with progress
      PreviewLoadingDialog.show(
        context,
        (onProgress) => previewNotifier.loadTimelinePreview(
          timeline,
          mediaLibrary,
          onProgress: onProgress,
        ),
      ).then((success) {
        if (!context.mounted || !success) return;
        previewNotifier.seekTo(timeline.currentPosition);
        previewNotifier.togglePlayPause();
      });
      return;
    }

    // If already playing, pause. Otherwise check if we have a valid video
    if (!previewState.isPlaying) {
      previewNotifier.seekTo(timeline.currentPosition);
    } else {
      // When pausing, sync timeline position with preview position
      final timelineNotifier = ref.read(timelineProvider.notifier);
      timelineNotifier.setCurrentPosition(previewState.currentPosition);
    }

    previewNotifier.togglePlayPause();
  }
}
