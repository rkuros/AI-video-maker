import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';
import 'package:video_editor/core/services/project_service.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';

/// Provider for project service
final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService();
});

/// State for the current project
class ProjectState {
  final Project? project;
  final String? filePath;
  final bool isModified;
  final bool isSaving;
  final String? error;

  const ProjectState({
    this.project,
    this.filePath,
    this.isModified = false,
    this.isSaving = false,
    this.error,
  });

  ProjectState copyWith({
    Project? project,
    String? filePath,
    bool? isModified,
    bool? isSaving,
    String? error,
    bool clearFilePath = false,
    bool clearError = false,
  }) {
    return ProjectState(
      project: project ?? this.project,
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      isModified: isModified ?? this.isModified,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasProject => project != null;
}

/// Notifier for project management
class ProjectNotifier extends StateNotifier<ProjectState> {
  final Ref ref;
  Timer? _autoSaveTimer;

  ProjectNotifier(this.ref) : super(const ProjectState()) {
    _startAutoSave();
  }

  /// Create a new project
  void createNewProject(
    String name, {
    Resolution resolution = Resolution.r1080p,
    int frameRate = 30,
    Duration? maxDuration,
  }) {
    final project = Project(
      name: name,
      defaultExportSettings: ExportSettings(
        resolution: resolution,
        frameRate: frameRate,
      ),
      maxDuration: maxDuration ?? const Duration(minutes: 5),
    );

    // Clear timeline and media library
    ref.read(timelineProvider.notifier).clear();
    ref.read(mediaLibraryProvider.notifier).clear();

    state = ProjectState(
      project: project,
      isModified: false,
    );
  }

  /// Save the current project
  Future<void> saveProject({String? customPath}) async {
    if (state.project == null) return;

    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final service = ref.read(projectServiceProvider);

      // Get current state from providers
      final timeline = ref.read(timelineProvider);
      final mediaLibrary = ref.read(mediaLibraryProvider);

      // Update project with current state
      final updatedProject = state.project!.copyWith(
        timeline: timeline,
        mediaLibrary: mediaLibrary,
      ).touch();

      // Determine file path
      String filePath;
      if (customPath != null) {
        filePath = customPath;
      } else if (state.filePath != null) {
        filePath = state.filePath!;
      } else {
        filePath = await service.getDefaultFilePath(updatedProject.name);
      }

      // Save project
      await service.saveProject(updatedProject, filePath);

      state = state.copyWith(
        project: updatedProject,
        filePath: filePath,
        isModified: false,
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save project: $e',
      );
    }
  }

  /// Load a project from file
  Future<void> loadProject(String filePath) async {
    state = state.copyWith(clearError: true);

    try {
      final service = ref.read(projectServiceProvider);
      final project = await service.loadProject(filePath);

      // Load timeline
      ref.read(timelineProvider.notifier).loadTimeline(project.timeline);

      // Load media library
      ref.read(mediaLibraryProvider.notifier).loadItems(project.mediaLibrary);

      // Detect missing source files early (thumbnails will be regenerated in background).
      String? warning;
      final missing = <String>[];
      for (final item in project.mediaLibrary) {
        if (item.filePath.isEmpty) continue;
        if (!File(item.filePath).existsSync()) {
          missing.add(item.name);
        }
      }
      if (missing.isNotEmpty) {
        final sample = missing.take(3).join(', ');
        warning =
            'Missing media files: ${missing.length} (e.g. $sample). Please re-link or re-import.';
      }

      state = ProjectState(
        project: project,
        filePath: filePath,
        isModified: false,
        error: warning,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to load project: $e',
      );
    }
  }

  /// Mark project as modified
  void markAsModified() {
    if (!state.isModified && state.project != null) {
      state = state.copyWith(isModified: true);
    }
  }

  /// Update project settings
  void updateProjectSettings({
    String? name,
    Resolution? resolution,
    int? frameRate,
    Duration? maxDuration,
    bool clearMaxDuration = false,
  }) {
    if (state.project == null) return;

    final currentSettings = state.project!.defaultExportSettings;
    final updatedSettings = currentSettings.copyWith(
      resolution: resolution,
      frameRate: frameRate,
    );

    final updatedProject = state.project!.copyWith(
      name: name,
      defaultExportSettings: updatedSettings,
      maxDuration: maxDuration,
      clearMaxDuration: clearMaxDuration,
    ).touch();

    state = state.copyWith(
      project: updatedProject,
      isModified: true,
    );
  }

  /// Close current project
  void closeProject() {
    _stopAutoSave();

    // Clear timeline and media library
    ref.read(timelineProvider.notifier).clear();
    ref.read(mediaLibraryProvider.notifier).clear();

    state = const ProjectState();

    _startAutoSave();
  }

  /// Auto-save project
  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _performAutoSave(),
    );
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  Future<void> _performAutoSave() async {
    if (state.hasProject && state.isModified && !state.isSaving) {
      await saveProject();
    }
  }

  @override
  void dispose() {
    _stopAutoSave();
    super.dispose();
  }
}

/// Provider for project state
final projectProvider =
    StateNotifierProvider<ProjectNotifier, ProjectState>((ref) {
  return ProjectNotifier(ref);
});

/// Provider for checking if project is modified
final isProjectModifiedProvider = Provider<bool>((ref) {
  return ref.watch(projectProvider).isModified;
});

/// Provider for checking if project exists
final hasProjectProvider = Provider<bool>((ref) {
  return ref.watch(projectProvider).hasProject;
});
