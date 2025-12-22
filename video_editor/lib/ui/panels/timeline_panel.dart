import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/audio_provider.dart';
import 'package:video_editor/core/logic/preview_provider.dart';
import 'package:video_editor/core/logic/project_provider.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/auto_editor_service.dart';
import 'package:video_editor/core/services/beat_analyzer_service.dart';
import 'package:video_editor/core/services/highlight_generator_service.dart';
import 'package:video_editor/core/engines/ffmpeg_video_engine.dart';
import 'package:video_editor/ui/dialogs/highlight_editor_dialog.dart';
import 'package:video_editor/ui/dialogs/highlight_generation_dialog.dart';
import 'package:video_editor/ui/dialogs/preview_loading_dialog.dart';

/// Timeline panel for editing video clips
class TimelinePanel extends ConsumerStatefulWidget {
  const TimelinePanel({super.key});

  @override
  ConsumerState<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends ConsumerState<TimelinePanel> {
  double _pixelsPerSecond = 50.0; // Zoom level
  static const double _trackHeaderWidth = 120.0;
  final ScrollController _scrollController = ScrollController();
  final AutoEditorService _autoEditorService = AutoEditorService();
  final FFmpegVideoEngine _videoEngine = FFmpegVideoEngine();
  final Map<String, List<double>> _waveformCache = {};
  final Set<String> _waveformLoading = {};
  final Map<String, GlobalKey> _trackContentKeys = {};
  final GlobalKey _emptyVideoDropKey = GlobalKey();
  final GlobalKey _emptyAudioDropKey = GlobalKey();
  String? _draggingClipId;
  Duration? _draggingClipStartTime;
  double? _dragStartGlobalDx;

  // Trim state
  String? _trimmingClipId;
  String? _trimmingTrackId;
  Duration? _originalSourceStart;
  Duration? _originalSourceDuration;
  Duration? _originalStartTime;
  Duration? _originalEndTime;
  Duration? _originalMediaDuration;
  double? _trimStartGlobalDx;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final videoTracks = ref.watch(videoTracksProvider);
    final audioTracks = ref.watch(audioTracksProvider);

    // Use preview position when playing, otherwise use timeline position
    final previewState = ref.watch(previewProvider);
    final currentPosition = previewState.isPlaying
        ? previewState.currentPosition
        : timeline.currentPosition;

    return Container(
      color: Colors.grey[850],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(timeline),
          const Divider(height: 1),
          Expanded(
            child: _buildTimelineContent(
              videoTracks,
              audioTracks,
              currentPosition,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Timeline timeline) {
    final timelineNotifier = ref.read(timelineProvider.notifier);
    final previewState = ref.watch(previewProvider);

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        children: [
          const Text(
            'Timeline',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          // Add track buttons
          IconButton(
            icon: const Icon(Icons.video_library),
            onPressed: () {
              timelineNotifier.addTrack(TrackType.video, name: 'Video Track');
            },
            tooltip: 'Add Video Track',
            iconSize: 20,
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack),
            onPressed: () {
              timelineNotifier.addTrack(TrackType.audio, name: 'Audio Track');
            },
            tooltip: 'Add Audio Track',
            iconSize: 20,
          ),
          const VerticalDivider(),
          // Playback controls
          IconButton(
            icon: Icon(
              previewState.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: _togglePlayback,
            tooltip: previewState.isPlaying ? 'Pause' : 'Play',
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stopPlayback,
            tooltip: 'Stop',
          ),
          const SizedBox(width: 8),
          // Preview quality preset
          PopupMenuButton<PreviewQualityPreset>(
            tooltip: 'Preview Quality',
            initialValue: previewState.timelinePreviewPreset,
            onSelected: (preset) {
              ref.read(previewProvider.notifier).setTimelinePreviewPreset(preset);
            },
            itemBuilder: (context) => PreviewQualityPreset.values
                .map(
                  (preset) => PopupMenuItem(
                    value: preset,
                    child: Row(
                      children: [
                        if (preset == previewState.timelinePreviewPreset)
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.high_quality, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    previewState.timelinePreviewPreset.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Current time display
          Text(
            _formatDuration(timeline.currentPosition),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const Text(' / '),
          Text(
            _formatDuration(timeline.duration),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(width: 32),
          // Auto Import button
          IconButton(
            icon: const Icon(Icons.library_add),
            onPressed: _autoImportMedia,
            tooltip: 'Auto Import',
          ),
          // Highlight editor button
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _openHighlightEditor,
            tooltip: 'Edit Highlights',
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _autoEditTimeline,
            tooltip: 'Auto Edit',
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion),
            onPressed: _generateHighlightTimeline,
            tooltip: 'Generate Highlight',
          ),
          const VerticalDivider(),
          // Zoom controls
          const Text('Zoom: '),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: _zoomOut,
            tooltip: 'Zoom Out',
            iconSize: 20,
          ),
          SizedBox(
            width: 100,
            child: Slider(
              value: _pixelsPerSecond,
              min: 10,
              max: 200,
              onChanged: (value) {
                setState(() {
                  _pixelsPerSecond = value;
                });
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _zoomIn,
            tooltip: 'Zoom In',
            iconSize: 20,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTimelineContent(
    List<Track> videoTracks,
    List<Track> audioTracks,
    Duration currentPosition,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Stack(
            children: [
              SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _getTimelineWidth(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Time ruler
                    _buildTimeRuler(),
                    const Divider(height: 1),
                    // Video tracks
                    if (videoTracks.isEmpty)
                      _buildEmptyTrackPlaceholder('Add video tracks', TrackType.video)
                    else
                      ...videoTracks.map((track) => _buildTrack(track)),
                    const Divider(height: 2, thickness: 2),
                    // Audio tracks
                    if (audioTracks.isEmpty)
                      _buildEmptyTrackPlaceholder('Add audio tracks', TrackType.audio)
                    else
                      ...audioTracks.map((track) => _buildTrack(track)),
                  ],
                ),
              ),
            ),
            // Max duration marker
            _buildMaxDurationMarker(),
            // Playhead
            Positioned(
              left: _trackHeaderWidth + _durationToPixels(currentPosition),
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                color: Colors.red,
              ),
            ),
          ],
        ),
        );
      },
    );
  }

  Widget _buildTimeRuler() {
    final timeline = ref.watch(timelineProvider);
    final totalSeconds = timeline.duration.inSeconds;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final x = details.localPosition.dx - _trackHeaderWidth;
            if (x < 0) return;
            final position = _pixelsToDuration(x);
            ref.read(timelineProvider.notifier).setCurrentPosition(position);
            final previewState = ref.read(previewProvider);
            if (previewState.timelinePreviewPath != null &&
                previewState.currentVideoPath == previewState.timelinePreviewPath) {
              ref.read(previewProvider.notifier).seekTo(position);
            }
          },
          child: Container(
            height: 30,
            color: Colors.grey[900],
            child: Row(
              children: [
                SizedBox(width: _trackHeaderWidth),
                Expanded(
                  child: CustomPaint(
                    painter: _TimeRulerPainter(
                      totalSeconds: totalSeconds,
                      pixelsPerSecond: _pixelsPerSecond,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrack(Track track) {
    final contentKey =
        _trackContentKeys.putIfAbsent(track.id, () => GlobalKey());
    return DragTarget<MediaItem>(
      onAcceptWithDetails: (details) {
        if (track.isLocked) return;
        final startTime = _globalOffsetToTimelinePosition(
          contentKey,
          details.offset,
        );
        _addClipToTrack(track.id, details.data, startTime: startTime);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty && !track.isLocked
                ? Colors.blue.withValues(alpha: 0.2)
                : Colors.grey[800],
            border: Border(
              bottom: BorderSide(color: Colors.grey[700]!),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Track header
              Container(
                width: _trackHeaderWidth,
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[900],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          track.type == TrackType.video
                              ? Icons.videocam
                              : Icons.audiotrack,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            track.name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            track.isMuted ? Icons.volume_off : Icons.volume_up,
                            size: 16,
                          ),
                          onPressed: () => _toggleTrackMute(track.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            track.isLocked ? Icons.lock : Icons.lock_open,
                            size: 16,
                          ),
                          onPressed: () => _toggleTrackLock(track.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Track content
              Expanded(
                child: GestureDetector(
                  onTapDown: (details) {
                    final position = _globalOffsetToTimelinePosition(
                      contentKey,
                      details.globalPosition,
                    );
                    ref.read(timelineProvider.notifier).setCurrentPosition(position);
                    final previewState = ref.read(previewProvider);
                    if (previewState.timelinePreviewPath != null &&
                        previewState.currentVideoPath ==
                            previewState.timelinePreviewPath) {
                      ref.read(previewProvider.notifier).seekTo(position);
                    }
                  },
                  child: Container(
                    key: contentKey,
                    color: Colors.transparent,
                    child: Stack(
                      children: track.clips.map((clip) {
                        return _buildClip(track, clip, contentKey);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClip(Track track, Clip clip, GlobalKey trackContentKey) {
    final mediaLibrary = ref.watch(mediaLibraryProvider);
    final selection = ref.watch(selectionProvider);
    final mediaItem = mediaLibrary.firstWhere(
      (item) => item.id == clip.mediaItemId,
      orElse: () => MediaItem(
        filePath: '',
        name: 'Unknown',
        type: MediaType.video,
        duration: Duration.zero,
      ),
    );

	    final left = _durationToPixels(clip.startTime);
	    final width = _durationToPixels(clip.duration);
	    final isSelected = selection.selectedClipId == clip.id;
	    final isAudioClip = mediaItem.type == MediaType.audio;
      final fileExists =
          mediaItem.filePath.isNotEmpty && File(mediaItem.filePath).existsSync();
      final dragInset = isSelected && !track.isLocked ? 8.0 : 0.0;

    if (isAudioClip) {
      _ensureWaveform(mediaItem);
    }

		    return Positioned(
		      left: left,
		      top: 4,
          child: SizedBox(
            width: width,
	            height: 72,
	            child: Stack(
	              children: [
                  // Visual layer (always full-width)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue[700] : Colors.blue[900],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? Colors.yellow : Colors.blue[700]!,
                            width: isSelected ? 2 : 1,
                          ),
                          image: !isAudioClip && mediaItem.thumbnail != null
                              ? DecorationImage(
                                  image: MemoryImage(mediaItem.thumbnail!),
                                  fit: BoxFit.cover,
                                  opacity: 0.3,
                                )
                              : null,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                mediaItem.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                _formatDuration(clip.duration),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            if (isAudioClip)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: SizedBox(
                                  height: 16,
                                  child: _buildWaveform(mediaItem),
                                ),
                              ),
                            if (clip.effects.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${clip.effects.length} effects',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green[300],
                                ),
                              ),
                            ],
                            // Show transition indicators
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (clip.inTransition != null)
                                  Container(
                                    margin: const EdgeInsets.only(
                                      right: 4,
                                      top: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[700],
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.arrow_forward,
                                          size: 8,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'In',
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (clip.outTransition != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[700],
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.arrow_back,
                                          size: 8,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'Out',
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!fileExists)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Missing',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Drag/selection hit layer (inset when selected so trim handles win).
                  Positioned(
                    left: dragInset,
                    right: dragInset,
                    top: 0,
                    bottom: 0,
                    child: Listener(
                      onPointerDown: (event) {
                        // Select clip when clicked or dragged
	                    ref
	                        .read(selectionProvider.notifier)
	                        .selectClip(clip.id, track.id);
                    _draggingClipId = clip.id;
                    _draggingClipStartTime = clip.startTime;
                    _dragStartGlobalDx = event.position.dx;
                  },
                  child: Draggable<Clip>(
                    data: clip,
                    maxSimultaneousDrags: track.isLocked ? 0 : null,
                    onDragEnd: (details) {
                      if (track.isLocked) return;

                      final startTime = _draggingClipId == clip.id &&
                              _draggingClipStartTime != null &&
                              _dragStartGlobalDx != null
                          ? (_draggingClipStartTime! +
                              _pixelsToDurationDelta(
                                details.offset.dx - _dragStartGlobalDx!,
                              ))
                          : _globalOffsetToTimelinePosition(
                              trackContentKey,
                              details.offset,
                            );

                      _draggingClipId = null;
                      _draggingClipStartTime = null;
                      _dragStartGlobalDx = null;

                      var clamped = startTime;
                      if (clamped < Duration.zero) clamped = Duration.zero;

                      // Insert without trimming: keep this clip's duration and let the
                      // timeline model ripple-shift other clips to the right as needed.
                      ref
                          .read(timelineProvider.notifier)
                          .moveClip(clip.id, clamped);
                    },
                    feedback: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: width,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white, width: 2),
                          image: !isAudioClip && mediaItem.thumbnail != null
                              ? DecorationImage(
                                  image: MemoryImage(mediaItem.thumbnail!),
                                  fit: BoxFit.cover,
                                  opacity: 0.3,
                                )
                              : null,
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              mediaItem.name,
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Container(
                        color: Colors.transparent,
                    ),
                    child: Container(
                      key: ValueKey('clip_hit_${clip.id}'),
                      color: Colors.transparent,
                    ),
                  ),
                ),
                  ),
                // Left trim handle (outside Draggable to avoid gesture conflicts)
                if (isSelected && !track.isLocked)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeft,
                      child: GestureDetector(
                        key: ValueKey('trim_left_${clip.id}'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragDown: (details) {
                          ref
                              .read(selectionProvider.notifier)
                              .selectClip(clip.id, track.id);
                          _startTrimLeft(clip, track.id, details);
                        },
                        onHorizontalDragUpdate: (details) {
                          _updateTrimLeft(details);
                        },
                        onHorizontalDragEnd: (details) {
                          _endTrim();
                        },
                        child: Container(
                          width: 8,
                          decoration: BoxDecoration(
                            color: Colors.yellow.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              bottomLeft: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 2,
                              height: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Right trim handle (outside Draggable to avoid gesture conflicts)
                if (isSelected && !track.isLocked)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeRight,
                      child: GestureDetector(
                        key: ValueKey('trim_right_${clip.id}'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragDown: (details) {
                          ref
                              .read(selectionProvider.notifier)
                              .selectClip(clip.id, track.id);
                          _startTrimRight(clip, track.id, details);
                        },
                        onHorizontalDragUpdate: (details) {
                          _updateTrimRight(details);
                        },
                        onHorizontalDragEnd: (details) {
                          _endTrim();
                        },
                        child: Container(
                          width: 8,
                          decoration: BoxDecoration(
                            color: Colors.yellow.withValues(alpha: 0.8),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 2,
                              height: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
		    );
		  }

  Widget _buildEmptyTrackPlaceholder(String message, TrackType type) {
    final contentKey = type == TrackType.video ? _emptyVideoDropKey : _emptyAudioDropKey;

    // NOTE: This is inside a vertical SingleChildScrollView, so we must keep a
    // bounded height to avoid "infinite height constraints" with stretch.
    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[700]!),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _trackHeaderWidth,
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[900],
            child: Center(
              child: Text(
                type == TrackType.video ? 'Video' : 'Audio',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: DragTarget<MediaItem>(
              onAcceptWithDetails: (details) {
                // Create a new track and add the clip
                final timelineNotifier = ref.read(timelineProvider.notifier);
                timelineNotifier.addTrack(type, name: '${type.name} Track');

                // Get the newly created track
                final tracks = type == TrackType.video
                    ? ref.read(videoTracksProvider)
                    : ref.read(audioTracksProvider);

                if (tracks.isNotEmpty) {
                  final newTrack = tracks.last;
                  final startTime =
                      _globalOffsetToTimelinePosition(contentKey, details.offset);
                  _addClipToTrack(newTrack.id, details.data, startTime: startTime);
                }
              },
              builder: (context, candidateData, rejectedData) {
                return Container(
                  key: contentKey,
                  color: candidateData.isNotEmpty
                      ? Colors.blue.withValues(alpha: 0.2)
                      : Colors.grey[800],
                  child: Center(
                    child: Text(
                      candidateData.isNotEmpty ? 'Drop to create track' : message,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addClipToTrack(
    String trackId,
    MediaItem mediaItem, {
    Duration? startTime,
  }) {
    final timelineNotifier = ref.read(timelineProvider.notifier);
    final timeline = ref.read(timelineProvider);

    // Calculate the start time for the new clip (end of the track)
    final track = timeline.getTrack(trackId);
    if (track == null) return;
    if (track.isLocked) return;

    var desiredStart = startTime ?? track.duration;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;

    final clip = Clip(
      mediaItemId: mediaItem.id,
      startTime: desiredStart,
      endTime: desiredStart + mediaItem.duration,
      sourceStart: Duration.zero,
      sourceDuration: mediaItem.duration,
    );

    // Insert without trimming: keep this clip's duration, and only push other
    // clips if needed (handled in the timeline model).
    timelineNotifier.addClip(trackId, clip);
  }

  void _toggleTrackMute(String trackId) {
    final audioOps = ref.read(audioOperationsProvider);
    audioOps.toggleTrackMute(trackId);
  }

  void _toggleTrackLock(String trackId) {
    final audioOps = ref.read(audioOperationsProvider);
    audioOps.toggleTrackLock(trackId);
  }

  void _togglePlayback() {
    final previewState = ref.read(previewProvider);
    final previewNotifier = ref.read(previewProvider.notifier);
    final timeline = ref.read(timelineProvider);
    final mediaLibrary = ref.read(mediaLibraryProvider);

    if (timeline.tracks.isEmpty || timeline.duration == Duration.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add clips to the timeline before playing'),
        ),
      );
      return;
    }

    if (previewState.timelinePreviewPath == null ||
        previewState.currentVideoPath != previewState.timelinePreviewPath) {
      // Show loading dialog with progress
      PreviewLoadingDialog.show(
        context,
        (onProgress) => previewNotifier.loadTimelinePreview(
          timeline,
          mediaLibrary,
          onProgress: onProgress,
        ),
      ).then((success) {
        if (!mounted || !success) return;
        previewNotifier.seekTo(timeline.currentPosition);
        previewNotifier.togglePlayPause();
      });
      return;
    }

    if (!previewState.isPlaying) {
      previewNotifier.seekTo(timeline.currentPosition);
    } else {
      // When pausing, sync timeline position with preview position
      final timelineNotifier = ref.read(timelineProvider.notifier);
      timelineNotifier.setCurrentPosition(previewState.currentPosition);
    }

    previewNotifier.togglePlayPause();
  }

  void _stopPlayback() {
    final timelineNotifier = ref.read(timelineProvider.notifier);
    timelineNotifier.setCurrentPosition(Duration.zero);

    // Stop preview panel
    final previewNotifier = ref.read(previewProvider.notifier);
    previewNotifier.pause();
    previewNotifier.seekTo(Duration.zero);
  }

  void _zoomIn() {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * 1.2).clamp(10.0, 200.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond / 1.2).clamp(10.0, 200.0);
    });
  }

  void _ensureWaveform(MediaItem item) {
    if (_waveformCache.containsKey(item.id) || _waveformLoading.contains(item.id)) {
      return;
    }
    _waveformLoading.add(item.id);
    _videoEngine
        .extractWaveform(item.filePath, sampleCount: 200)
        .then((waveform) {
      if (!mounted) return;
      setState(() {
        _waveformCache[item.id] = waveform;
      });
    }).whenComplete(() {
      _waveformLoading.remove(item.id);
    });
  }

  Widget _buildWaveform(MediaItem item) {
    final waveform = _waveformCache[item.id];
    if (waveform == null || waveform.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[700],
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return CustomPaint(
      painter: _WaveformPainter(waveform),
    );
  }

  Widget _buildMaxDurationMarker() {
    final projectState = ref.watch(projectProvider);
    final timeline = ref.watch(timelineProvider);

    if (!projectState.hasProject || projectState.project!.maxDuration == null) {
      return const SizedBox.shrink();
    }

    final maxDuration = projectState.project!.maxDuration!;
    final actualDuration = timeline.duration;
    final maxDurationX = _durationToPixels(maxDuration);
    final isExceeding = actualDuration > maxDuration;

    return Positioned(
      left: _trackHeaderWidth + maxDurationX,
      top: 0,
      bottom: 0,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isExceeding ? Colors.orange[700] : Colors.yellow[700],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Max',
              style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: isExceeding ? Colors.orange[700] : Colors.yellow[700],
            ),
          ),
        ],
      ),
    );
  }

  double _durationToPixels(Duration duration) {
    return duration.inMilliseconds / 1000 * _pixelsPerSecond;
  }

  Duration _pixelsToDuration(double pixels) {
    if (pixels <= 0) return Duration.zero;
    final seconds = pixels / _pixelsPerSecond;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration _pixelsToDurationDelta(double pixels) {
    final seconds = pixels / _pixelsPerSecond;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration _globalOffsetToTimelinePosition(GlobalKey key, Offset globalOffset) {
    final context = key.currentContext;
    if (context == null) return Duration.zero;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Duration.zero;
    final local = box.globalToLocal(globalOffset);
    return _pixelsToDuration(local.dx);
  }

  double _getTimelineWidth() {
    final timeline = ref.watch(timelineProvider);
    final projectState = ref.watch(projectProvider);

    // Use maxDuration if set, otherwise use actual timeline duration
    Duration displayDuration = timeline.duration;
    if (projectState.hasProject && projectState.project!.maxDuration != null) {
      final maxDuration = projectState.project!.maxDuration!;
      // Show at least maxDuration or actual duration, whichever is larger
      if (maxDuration > displayDuration) {
        displayDuration = maxDuration;
      }
    }

    final contentWidth = _durationToPixels(displayDuration).clamp(800.0, double.infinity);
    return _trackHeaderWidth + contentWidth;
  }

  Future<void> _openHighlightEditor() async {
    final videoTracks = ref.read(videoTracksProvider);

    if (videoTracks.isEmpty) return;

    // Get clips from the first video track
    final track = videoTracks.first;
    if (track.clips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No clips in timeline to edit'),
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => HighlightEditorDialog(
        trackId: track.id,
        highlightClips: track.clips,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Highlight clips updated'),
        ),
      );
    }
  }

  Future<void> _autoEditTimeline() async {
    final mediaLibrary = ref.read(mediaLibraryProvider);
    if (mediaLibrary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import media to auto-edit')),
      );
      return;
    }

    final timeline =
        await _autoEditorService.createAutoTimeline(mediaLibrary);

    ref.read(timelineProvider.notifier).loadTimeline(timeline);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto edit completed')),
      );
    }
  }

  Future<void> _generateHighlightTimeline() async {
    final timeline = ref.read(timelineProvider);
    if (timeline.videoTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video clips to generate highlights')),
      );
      return;
    }

    final mediaLibrary = ref.read(mediaLibraryProvider);
    final request = await showDialog<HighlightGenerationRequest>(
      context: context,
      builder: (context) => HighlightGenerationDialog(mediaLibrary: mediaLibrary),
    );
    if (request == null) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future.microtask(() async {
          try {
            final service = HighlightGeneratorService(
              BeatAnalyzerService(FFmpegVideoEngine()),
              mediaLibrary,
            );
            final highlightTimeline = await service.generateHighlight(
              baseTimeline: timeline,
              targetDuration: request.targetDuration,
              mode: request.mode,
              pattern: request.pattern,
              preferences: request.preferences,
              bgmTrack: request.bgm,
            );

            if (!mounted) return;
            ref.read(timelineProvider.notifier).loadTimeline(highlightTimeline);
            Navigator.of(context).pop();
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('Highlight timeline generated')),
            );
          } catch (e) {
            if (!mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(content: Text('Highlight generation failed: $e')),
            );
          }
        });

        return const AlertDialog(
          title: Text('ハイライト生成中'),
          content: SizedBox(
            height: 72,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _autoImportMedia() async {
    final mediaLibrary = ref.read(mediaLibraryProvider);

    // Filter video items only
    final videoItems = mediaLibrary
        .where((item) => item.type == MediaType.video)
        .toList();

    if (videoItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video files in media library')),
      );
      return;
    }

    // Sort by file modification time (oldest first)
    videoItems.sort((a, b) {
      try {
        final fileA = File(a.filePath);
        final fileB = File(b.filePath);
        final statA = fileA.statSync();
        final statB = fileB.statSync();
        // Compare modification times (oldest first)
        return statA.modified.compareTo(statB.modified);
      } catch (e) {
        // Fallback to name sorting if file stat fails
        return a.name.compareTo(b.name);
      }
    });

    // Clear timeline
    ref.read(timelineProvider.notifier).clear();

    // Create a video track
    ref.read(timelineProvider.notifier).addTrack(
      TrackType.video,
      name: 'Auto Import Track',
    );

    // Get the created track
    final timeline = ref.read(timelineProvider);
    if (timeline.videoTracks.isEmpty) return;

    final trackId = timeline.videoTracks.first.id;

    // Add clips sequentially
    Duration currentTime = Duration.zero;
    for (final mediaItem in videoItems) {
      final clip = Clip(
        mediaItemId: mediaItem.id,
        startTime: currentTime,
        endTime: currentTime + mediaItem.duration,
        sourceStart: Duration.zero,
        sourceDuration: mediaItem.duration,
      );

      ref.read(timelineProvider.notifier).addClip(trackId, clip);
      currentTime += mediaItem.duration;
    }

    // Update project maxDuration to match total timeline duration
    final totalDuration = currentTime;
    final projectState = ref.read(projectProvider);
    if (projectState.hasProject) {
      ref.read(projectProvider.notifier).updateProjectSettings(
        maxDuration: totalDuration,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Auto imported ${videoItems.length} videos (${_formatDuration(totalDuration)})',
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final milliseconds = duration.inMilliseconds.remainder(1000) ~/ 10;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${milliseconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${milliseconds.toString().padLeft(2, '0')}';
    }
  }

  void _startTrimLeft(Clip clip, String trackId, DragDownDetails details) {
    final timeline = ref.read(timelineProvider);
    final track = timeline.getTrack(trackId);
    if (track == null || track.isLocked) return;
    final mediaLibrary = ref.read(mediaLibraryProvider);
    final mediaDuration = mediaLibrary
        .firstWhere(
          (item) => item.id == clip.mediaItemId,
          orElse: () => MediaItem(
            id: clip.mediaItemId,
            filePath: '',
            name: 'Unknown',
            type: MediaType.video,
            duration: Duration.zero,
          ),
        )
        .duration;
    setState(() {
      _trimmingClipId = clip.id;
      _trimmingTrackId = trackId;
      _originalSourceStart = clip.sourceStart;
      _originalSourceDuration = clip.sourceDuration;
      _originalStartTime = clip.startTime;
      _originalEndTime = clip.endTime;
      _originalMediaDuration = mediaDuration;
      _trimStartGlobalDx = details.globalPosition.dx;
    });
  }

  void _startTrimRight(Clip clip, String trackId, DragDownDetails details) {
    final timeline = ref.read(timelineProvider);
    final track = timeline.getTrack(trackId);
    if (track == null || track.isLocked) return;
    final mediaLibrary = ref.read(mediaLibraryProvider);
    final mediaDuration = mediaLibrary
        .firstWhere(
          (item) => item.id == clip.mediaItemId,
          orElse: () => MediaItem(
            id: clip.mediaItemId,
            filePath: '',
            name: 'Unknown',
            type: MediaType.video,
            duration: Duration.zero,
          ),
        )
        .duration;
    setState(() {
      _trimmingClipId = clip.id;
      _trimmingTrackId = trackId;
      _originalSourceStart = clip.sourceStart;
      _originalSourceDuration = clip.sourceDuration;
      _originalStartTime = clip.startTime;
      _originalEndTime = clip.endTime;
      _originalMediaDuration = mediaDuration;
      _trimStartGlobalDx = details.globalPosition.dx;
    });
  }

  void _updateTrimLeft(DragUpdateDetails details) {
    if (_trimmingClipId == null || _trimmingTrackId == null) return;
    if (_originalSourceStart == null || _originalSourceDuration == null) return;
    if (_originalStartTime == null || _originalEndTime == null) return;
    if (_trimStartGlobalDx == null) return;
    final dx = details.globalPosition.dx - _trimStartGlobalDx!;

    final deltaDuration = _pixelsToDurationDelta(dx);

    // New start time (cannot go below zero)
    var newStartTime = _originalStartTime! + deltaDuration;
    if (newStartTime < Duration.zero) newStartTime = Duration.zero;
    if (newStartTime > _originalEndTime! - const Duration(milliseconds: 100)) {
      newStartTime = _originalEndTime! - const Duration(milliseconds: 100);
    }

    // New end time stays the same
    final newEndTime = _originalEndTime!;
    ref.read(timelineProvider.notifier).trimClip(_trimmingClipId!, newStartTime, newEndTime);
  }

  void _updateTrimRight(DragUpdateDetails details) {
    if (_trimmingClipId == null || _trimmingTrackId == null) return;
    if (_originalSourceStart == null || _originalSourceDuration == null) return;
    if (_originalStartTime == null || _originalEndTime == null) return;
    if (_trimStartGlobalDx == null) return;
    final dx = details.globalPosition.dx - _trimStartGlobalDx!;

    final deltaDuration = _pixelsToDurationDelta(dx);

    final mediaDuration = _originalMediaDuration ?? Duration.zero;
    final availableFromStart = mediaDuration > Duration.zero
        ? (mediaDuration - _originalSourceStart!)
        : (_originalEndTime! - _originalStartTime!);
    final maxEndTime = _originalStartTime! + availableFromStart;
    var newEndTime = _originalEndTime! + deltaDuration;
    if (newEndTime < _originalStartTime! + const Duration(milliseconds: 100)) {
      newEndTime = _originalStartTime! + const Duration(milliseconds: 100);
    }
    if (newEndTime > maxEndTime) {
      newEndTime = maxEndTime;
    }

    // Start time stays the same
    final newStartTime = _originalStartTime!;
    ref.read(timelineProvider.notifier).trimClip(_trimmingClipId!, newStartTime, newEndTime);
  }

  void _endTrim() {
    setState(() {
      _trimmingClipId = null;
      _trimmingTrackId = null;
      _originalSourceStart = null;
      _originalSourceDuration = null;
      _originalStartTime = null;
      _originalEndTime = null;
      _originalMediaDuration = null;
      _trimStartGlobalDx = null;
    });
  }
}

/// Custom painter for time ruler
class _TimeRulerPainter extends CustomPainter {
  final int totalSeconds;
  final double pixelsPerSecond;

  _TimeRulerPainter({
    required this.totalSeconds,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw tick marks and labels
    for (int i = 0; i <= totalSeconds; i++) {
      final x = i * pixelsPerSecond;

      // Draw major tick every 5 seconds, minor tick every second
      if (i % 5 == 0) {
        canvas.drawLine(
          Offset(x, size.height - 15),
          Offset(x, size.height),
          paint,
        );

        // Draw time label
        textPainter.text = TextSpan(
          text: _formatTime(i),
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 5),
        );
      } else {
        canvas.drawLine(
          Offset(x, size.height - 8),
          Offset(x, size.height),
          paint..strokeWidth = 0.5,
        );
        paint.strokeWidth = 1;
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) {
    return totalSeconds != oldDelegate.totalSeconds ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond;
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;

  _WaveformPainter(this.waveform);

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 1;

    final midY = size.height / 2;
    final step = size.width / max(1, waveform.length - 1);

    for (var i = 0; i < waveform.length; i++) {
      final x = i * step;
      final amplitude = (waveform[i].abs() * midY).clamp(0.0, midY);
      canvas.drawLine(
        Offset(x, midY - amplitude),
        Offset(x, midY + amplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform;
  }
}
