import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for selected items in the editor
class SelectionState {
  final String? selectedClipId;
  final String? selectedTrackId;

  const SelectionState({
    this.selectedClipId,
    this.selectedTrackId,
  });

  SelectionState copyWith({
    String? selectedClipId,
    String? selectedTrackId,
    bool clearClipId = false,
    bool clearTrackId = false,
  }) {
    return SelectionState(
      selectedClipId: clearClipId ? null : (selectedClipId ?? this.selectedClipId),
      selectedTrackId: clearTrackId ? null : (selectedTrackId ?? this.selectedTrackId),
    );
  }

  bool get hasSelection => selectedClipId != null;
}

/// Notifier for selection state
class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(const SelectionState());

  /// Select a clip and its track
  void selectClip(String clipId, String trackId) {
    state = SelectionState(
      selectedClipId: clipId,
      selectedTrackId: trackId,
    );
  }

  /// Clear selection
  void clearSelection() {
    state = const SelectionState();
  }

  /// Check if a clip is selected
  bool isClipSelected(String clipId) {
    return state.selectedClipId == clipId;
  }
}

/// Provider for selection state
final selectionProvider =
    StateNotifierProvider<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});
