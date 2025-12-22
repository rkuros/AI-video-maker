import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_editor/ui/panels/media_library_panel.dart';
import 'package:video_editor/ui/panels/preview_panel.dart';
import 'package:video_editor/ui/panels/timeline_panel.dart';
import 'package:video_editor/ui/panels/properties_panel.dart';
import 'package:video_editor/ui/widgets/keyboard_shortcuts_help.dart';
import 'package:video_editor/core/logic/selection_provider.dart';
import 'package:video_editor/core/logic/project_provider.dart';
import 'package:video_editor/core/services/keyboard_shortcut_service.dart';
import 'package:video_editor/core/engines/export_engine.dart';
import 'package:video_editor/core/models/export_settings.dart';
import 'package:video_editor/core/models/enums.dart';
import 'package:video_editor/core/logic/timeline_provider.dart';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/ui/dialogs/project_settings_dialog.dart';
import 'package:video_editor/ui/dialogs/initialize_project_dialog.dart';
import 'package:flutter/services.dart';

/// Main window containing all UI panels
class MainWindow extends ConsumerStatefulWidget {
  const MainWindow({super.key});

  @override
  ConsumerState<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends ConsumerState<MainWindow> {
  final _shortcutService = KeyboardShortcutService();
  final _exportEngine = ExportEngine();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Request focus when clicking anywhere in the window
        _focusNode.requestFocus();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewProject,
            tooltip: 'New Project',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openProject,
            tooltip: 'Open Project',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProject,
            tooltip: 'Save Project',
          ),
          IconButton(
            icon: const Icon(Icons.save_as),
            onPressed: _saveProjectAs,
            tooltip: 'Save Project As',
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openProjectSettings,
            tooltip: 'Project Settings',
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportVideo,
            tooltip: 'Export Video',
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showKeyboardShortcuts,
            tooltip: 'Keyboard Shortcuts',
          ),
        ],
      ),
      body: Column(
        children: [
          // Top section with preview and media library
          Expanded(
            flex: 2,
            child: Row(
              children: [
                // Media library panel (left side)
                Expanded(
                  flex: 1,
                  child: _buildMediaLibraryPanel(),
                ),
                // Preview panel (center)
                Expanded(
                  flex: 2,
                  child: _buildPreviewPanel(),
                ),
                // Properties panel (right side)
                Expanded(
                  flex: 1,
                  child: _buildPropertiesPanel(),
                ),
              ],
            ),
          ),
          // Timeline panel (bottom)
          Expanded(
            flex: 1,
            child: _buildTimelinePanel(),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildMediaLibraryPanel() {
    return const MediaLibraryPanel();
  }

  Widget _buildPreviewPanel() {
    return const PreviewPanel();
  }

  Widget _buildPropertiesPanel() {
    final selection = ref.watch(selectionProvider);
    return PropertiesPanel(
      selectedClipId: selection.selectedClipId,
      selectedTrackId: selection.selectedTrackId,
    );
  }

  Widget _buildTimelinePanel() {
    return const TimelinePanel();
  }

  Widget _buildTitle() {
    final projectState = ref.watch(projectProvider);
    final timeline = ref.watch(timelineProvider);

    String title = 'Video Editor';
    if (projectState.hasProject) {
      title = projectState.project!.name;
      if (projectState.isModified) {
        title += ' *';
      }
    }

    // Settings info
    Widget? settingsInfo;
    if (projectState.hasProject) {
      final settings = projectState.project!.defaultExportSettings;
      final resolution = _getResolutionShortName(settings.resolution);
      final fps = '${settings.frameRate}fps';
      final duration = _formatDuration(
        projectState.project!.maxDuration ?? timeline.duration,
      );

      settingsInfo = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, size: 14, color: Colors.grey[300]),
                const SizedBox(width: 4),
                Text(
                  resolution,
                  style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                ),
                const SizedBox(width: 12),
                Icon(Icons.speed, size: 14, color: Colors.grey[300]),
                const SizedBox(width: 4),
                Text(
                  fps,
                  style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                ),
                const SizedBox(width: 12),
                Icon(Icons.schedule, size: 14, color: Colors.grey[300]),
                const SizedBox(width: 4),
                Text(
                  duration,
                  style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        if (settingsInfo != null) settingsInfo,
      ],
    );
  }

  Future<void> _createNewProject() async {
    final controller = TextEditingController();
    Resolution selectedResolution = Resolution.r1080p;
    int selectedFPS = 30;
    int selectedDurationMinutes = 5;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Project'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'My Video Project',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),

              const Text('Resolution', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButtonFormField<Resolution>(
                initialValue: selectedResolution,
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
                items: Resolution.values.map((res) {
                  return DropdownMenuItem(
                    value: res,
                    child: Text(_getResolutionName(res)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedResolution = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              const Text('Frame Rate', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: selectedFPS,
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
                items: const [24, 30, 60].map((fps) {
                  return DropdownMenuItem(
                    value: fps,
                    child: Text('$fps FPS'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedFPS = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              const Text('Timeline Duration', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: selectedDurationMinutes,
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
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 minute')),
                  DropdownMenuItem(value: 2, child: Text('2 minutes')),
                  DropdownMenuItem(value: 3, child: Text('3 minutes')),
                  DropdownMenuItem(value: 5, child: Text('5 minutes')),
                  DropdownMenuItem(value: 10, child: Text('10 minutes')),
                  DropdownMenuItem(value: -1, child: Text('Unlimited')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedDurationMinutes = value;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                'name': controller.text,
                'resolution': selectedResolution,
                'frameRate': selectedFPS,
                'maxDuration': selectedDurationMinutes == -1
                    ? null
                    : Duration(minutes: selectedDurationMinutes),
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'].isNotEmpty) {
      ref.read(projectProvider.notifier).createNewProject(
        result['name'],
        resolution: result['resolution'],
        frameRate: result['frameRate'],
        maxDuration: result['maxDuration'],
      );
    }
  }

  Future<void> _openProject() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vedproj'],
    );

    if (result != null && result.files.single.path != null) {
      await ref.read(projectProvider.notifier).loadProject(result.files.single.path!);

      if (mounted) {
        final error = ref.read(projectProvider).error;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    }
  }

  Future<void> _saveProject() async {
    final projectState = ref.read(projectProvider);

    // Check if project needs initialization
    if (!projectState.hasProject) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存するプロジェクトがありません')),
      );
      return;
    }

    final project = projectState.project!;

    // Check if project has a proper name (not default/untitled)
    if (project.name.isEmpty ||
        project.name.toLowerCase() == 'untitled' ||
        project.name.toLowerCase() == 'new project') {
      // Show initialization dialog
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => const InitializeProjectDialog(),
      );

      if (result == null || !mounted) return;

      // Update project with new settings (keeps timeline and media library)
      ref.read(projectProvider.notifier).updateProjectSettings(
        name: result['name'],
        resolution: result['resolution'],
        frameRate: result['frameRate'],
        maxDuration: result['maxDuration'],
      );
    }

    // Save the project
    await ref.read(projectProvider.notifier).saveProject();

    if (mounted) {
      final error = ref.read(projectProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロジェクトを保存しました')),
        );
      }
    }
  }

  Future<void> _saveProjectAs() async {
    final projectState = ref.read(projectProvider);

    // Save current timeline and media library before creating project
    final currentTimeline = ref.read(timelineProvider);
    final currentMediaLibrary = ref.read(mediaLibraryProvider);

    // Always show initialization dialog for Save As
    // This allows users to change the name even if project was already named
    final settings = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const InitializeProjectDialog(),
    );

    if (settings == null || !mounted) return;

    // If no project exists, create one with the settings
    if (!projectState.hasProject) {
      ref.read(projectProvider.notifier).createNewProject(
        settings['name'],
        resolution: settings['resolution'],
        frameRate: settings['frameRate'],
        maxDuration: settings['maxDuration'],
      );

      // Restore timeline and media library
      ref.read(timelineProvider.notifier).loadTimeline(currentTimeline);
      ref.read(mediaLibraryProvider.notifier).loadItems(currentMediaLibrary);
    } else {
      // Update existing project with new settings
      ref.read(projectProvider.notifier).updateProjectSettings(
        name: settings['name'],
        resolution: settings['resolution'],
        frameRate: settings['frameRate'],
        maxDuration: settings['maxDuration'],
      );
    }

    // Now ask for save location
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '名前を付けて保存',
      fileName: '${settings['name']}.vedproj',
    );

    if (result != null) {
      await ref.read(projectProvider.notifier).saveProject(customPath: result);

      if (mounted) {
        final error = ref.read(projectProvider).error;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('プロジェクトを保存しました')),
          );
        }
      }
    }
  }

  Future<void> _openProjectSettings() async {
    final projectState = ref.read(projectProvider);
    if (!projectState.hasProject) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project open')),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProjectSettingsDialog(
        currentSettings: projectState.project!.defaultExportSettings,
        currentProject: projectState.project!,
      ),
    );

    if (result != null) {
      ref.read(projectProvider.notifier).updateProjectSettings(
        resolution: result['resolution'],
        frameRate: result['frameRate'],
        maxDuration: result['maxDuration'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project settings updated')),
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    bool isEditingText() {
      final focusContext = FocusManager.instance.primaryFocus?.context;
      return focusContext != null &&
          (focusContext.widget is EditableText ||
              focusContext.findAncestorWidgetOfExactType<EditableText>() != null);
    }

    // Undo / Redo (Cmd+Z / Cmd+Shift+Z)
    if (_shortcutService.isUndo(event)) {
      if (isEditingText()) return KeyEventResult.ignored;
      ref.read(timelineProvider.notifier).undo();
      return KeyEventResult.handled;
    }
    if (_shortcutService.isRedo(event)) {
      if (isEditingText()) return KeyEventResult.ignored;
      ref.read(timelineProvider.notifier).redo();
      return KeyEventResult.handled;
    }

    // Delete selected clip (timeline)
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (isEditingText()) {
        return KeyEventResult.ignored;
      }

      final selection = ref.read(selectionProvider);
      if (selection.selectedClipId != null && selection.selectedTrackId != null) {
        ref
            .read(timelineProvider.notifier)
            .removeClip(selection.selectedTrackId!, selection.selectedClipId!);
        ref.read(selectionProvider.notifier).clearSelection();
        return KeyEventResult.handled;
      }
    }

    // Save
    if (_shortcutService.isSave(event)) {
      _saveProject();
      return KeyEventResult.handled;
    }

    // New
    if (_shortcutService.isNew(event)) {
      _createNewProject();
      return KeyEventResult.handled;
    }

    // Open
    if (_shortcutService.isOpen(event)) {
      _openProject();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _showKeyboardShortcuts() {
    showDialog(
      context: context,
      builder: (context) => const KeyboardShortcutsHelp(),
    );
  }

  Future<void> _exportVideo() async {
    final timeline = ref.read(timelineProvider);
    final mediaLibrary = ref.read(mediaLibraryProvider);
    if (timeline.videoTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video tracks to export')),
      );
      return;
    }

    final projectName = ref.read(projectProvider).project?.name ?? 'project';
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Video',
      fileName: '$projectName.mp4',
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov'],
    );

    if (outputPath == null) return;
    if (!mounted) return;

    final format = outputPath.toLowerCase().endsWith('.mov')
        ? VideoFormat.mov
        : VideoFormat.mp4;

    final projectState = ref.read(projectProvider);
    final defaultSettings = projectState.project?.defaultExportSettings;

    final settings = ExportSettings(
      outputPath: outputPath,
      format: format,
      resolution: defaultSettings?.resolution ?? Resolution.r1080p,
      quality: Quality.high,
      frameRate: defaultSettings?.frameRate ?? 30,
    );

    ExportProgress? currentProgress;
    bool started = false;

    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!started) {
              started = true;
              Future.microtask(() async {
                try {
                  await _exportEngine.exportTimeline(
                    timeline,
                    mediaLibrary,
                    settings,
                    (progress) {
                      setState(() {
                        currentProgress = progress;
                      });
                    },
                  );
                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context, e);
                  }
                }
              });
            }

            final progress = currentProgress?.progress ?? 0.0;

            return AlertDialog(
              title: const Text('動画をエクスポート中'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progress bar
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress > 0.95 ? Colors.green : Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Percentage
                    Text(
                      '${currentProgress?.percentage ?? 0}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Details
                    if (currentProgress != null) ...[
                      _buildInfoRow(
                        Icons.access_time,
                        '経過時間',
                        currentProgress!.elapsedFormatted,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.timer,
                        '残り時間',
                        currentProgress!.remainingFormatted,
                      ),
                      const SizedBox(height: 8),
                      if (currentProgress!.fps != null)
                        _buildInfoRow(
                          Icons.speed,
                          '処理速度',
                          '${currentProgress!.fps!.toStringAsFixed(1)} fps',
                        ),
                      if (currentProgress!.currentFrame != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.movie,
                          'フレーム',
                          '${currentProgress!.currentFrame}',
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _exportEngine.cancelExport();
                    Navigator.pop(context, 'cancelled');
                  },
                  child: const Text('キャンセル'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('エクスポートが完了しました')),
      );
    } else if (result == 'cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('エクスポートをキャンセルしました')),
      );
    } else if (result is Exception || result is Error) {
      final errorMsg = result.toString();
      if (errorMsg.contains('cancelled by user')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('エクスポートをキャンセルしました')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポートに失敗しました: $result')),
        );
      }
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _getResolutionName(Resolution resolution) {
    switch (resolution) {
      case Resolution.r480p:
        return '480p (854x480)';
      case Resolution.r720p:
        return '720p (1280x720)';
      case Resolution.r1080p:
        return '1080p (1920x1080)';
      case Resolution.r4k:
        return '4K (3840x2160)';
    }
  }

  String _getResolutionShortName(Resolution resolution) {
    switch (resolution) {
      case Resolution.r480p:
        return '480p';
      case Resolution.r720p:
        return '720p';
      case Resolution.r1080p:
        return '1080p';
      case Resolution.r4k:
        return '4K';
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m${seconds}s';
  }
}
