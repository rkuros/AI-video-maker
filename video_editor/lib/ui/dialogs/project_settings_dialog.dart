import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_editor/core/models/models.dart';

/// Dialog for editing project settings
class ProjectSettingsDialog extends ConsumerStatefulWidget {
  final ExportSettings currentSettings;
  final Project currentProject;

  const ProjectSettingsDialog({
    super.key,
    required this.currentSettings,
    required this.currentProject,
  });

  @override
  ConsumerState<ProjectSettingsDialog> createState() =>
      _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState
    extends ConsumerState<ProjectSettingsDialog> {
  late Resolution _selectedResolution;
  late int _selectedFPS;
  late int _selectedDurationMinutes;

  @override
  void initState() {
    super.initState();
    _selectedResolution = widget.currentSettings.resolution;
    _selectedFPS = widget.currentSettings.frameRate;

    // maxDuration から分単位を取得
    final maxDuration = widget.currentProject.maxDuration;
    if (maxDuration == null) {
      _selectedDurationMinutes = -1; // Unlimited
    } else {
      _selectedDurationMinutes = maxDuration.inMinutes;
      // リストにない値の場合は最も近い値
      if (![1, 2, 3, 5, 10].contains(_selectedDurationMinutes)) {
        _selectedDurationMinutes = 5;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project Settings'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Resolution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<Resolution>(
              initialValue: _selectedResolution,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
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
                    _selectedResolution = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            const Text('Frame Rate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _selectedFPS,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
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
                    _selectedFPS = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            const Text('Timeline Duration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _selectedDurationMinutes,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
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
                    _selectedDurationMinutes = value;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Maximum timeline length for this project',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'These settings will be used when exporting your video.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, {
            'resolution': _selectedResolution,
            'frameRate': _selectedFPS,
            'maxDuration': _selectedDurationMinutes == -1
                ? null
                : Duration(minutes: _selectedDurationMinutes),
          }),
          child: const Text('Save'),
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
}
