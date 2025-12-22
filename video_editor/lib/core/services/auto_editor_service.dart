import 'package:video_editor/core/models/models.dart';

/// Service for automatic video editing
class AutoEditorService {
  /// Create an automatic timeline from media items
  Future<Timeline> createAutoTimeline(List<MediaItem> mediaItems) async {
    if (mediaItems.isEmpty) {
      return Timeline();
    }

    // 1. Sort media files by creation date (using file path for now)
    final sortedItems = List<MediaItem>.from(mediaItems)
      ..sort((a, b) => a.name.compareTo(b.name));

    // 2. Separate videos and audio
    final videos =
        sortedItems.where((item) => item.type == MediaType.video).toList();
    final audios =
        sortedItems.where((item) => item.type == MediaType.audio).toList();

    // 3. Create timeline
    var timeline = Timeline();

    // Add video track
    if (videos.isNotEmpty) {
      final videoTrack = Track(type: TrackType.video, name: 'Video Track 1');
      timeline = timeline.addTrack(videoTrack);

      // Add video clips with transitions
      var currentTime = Duration.zero;
      TransitionEffect? previousTransition;

      for (var i = 0; i < videos.length; i++) {
        final item = videos[i];
        final clipDuration = _calculateOptimalClipDuration(item);

        // If previous clip had a transition, overlap this clip
        if (previousTransition != null) {
          currentTime -= previousTransition.duration;
        }

        final clip = Clip(
          mediaItemId: item.id,
          startTime: currentTime,
          endTime: currentTime + clipDuration,
          sourceStart: Duration.zero,
          sourceDuration: clipDuration,
        );

        // Add transition between clips (except first)
        Clip clipWithTransition = clip;
        TransitionEffect? currentTransition;
        if (i > 0) {
          currentTransition = _selectAppropriateTransition(i);
          clipWithTransition = clip.copyWith(inTransition: currentTransition);
        }

        timeline = timeline.addClipToTrack(videoTrack.id, clipWithTransition);
        currentTime += clipDuration;
        previousTransition = currentTransition;
      }
    }

    // 4. Add BGM if available
    if (audios.isNotEmpty) {
      final audioTrack = Track(type: TrackType.audio, name: 'BGM Track');
      timeline = timeline.addTrack(audioTrack);

      for (final audio in audios) {
        final clip = Clip(
          mediaItemId: audio.id,
          startTime: Duration.zero,
          endTime: audio.duration,
          sourceStart: Duration.zero,
          sourceDuration: audio.duration,
        );
        timeline = timeline.addClipToTrack(audioTrack.id, clip);
      }
    }

    return timeline;
  }

  /// Calculate optimal clip duration based on media type
  Duration _calculateOptimalClipDuration(MediaItem item) {
    // Use full duration if less than 10 seconds
    if (item.duration.inSeconds <= 10) {
      return item.duration;
    }

    // Otherwise, use first 5-10 seconds
    return Duration(seconds: 7);
  }

  /// Select appropriate transition based on clip index
  TransitionEffect _selectAppropriateTransition(int clipIndex) {
    // Alternate between different transitions
    final transitions = [
      TransitionType.crossFade,
      TransitionType.slide,
      TransitionType.fadeIn,
    ];

    final type = transitions[clipIndex % transitions.length];

    return TransitionEffect(
      name: type.name,
      duration: const Duration(milliseconds: 500),
      type: type,
    );
  }
}
