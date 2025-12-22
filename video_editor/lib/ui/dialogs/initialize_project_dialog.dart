import 'package:flutter/material.dart';
import 'package:video_editor/core/models/enums.dart';

/// Dialog for initializing an unnamed project before saving
class InitializeProjectDialog extends StatefulWidget {
  const InitializeProjectDialog({super.key});

  @override
  State<InitializeProjectDialog> createState() =>
      _InitializeProjectDialogState();
}

class _InitializeProjectDialogState extends State<InitializeProjectDialog> {
  final _nameController = TextEditingController();
  Resolution _selectedResolution = Resolution.r1080p;
  int _selectedFPS = 30;
  int _selectedDurationMinutes = 5;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('プロジェクト設定'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'プロジェクトを保存する前に、基本設定を入力してください。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Project Name
            const Text(
              'プロジェクト名',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例: My Video Project',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),

            // Resolution
            const Text(
              '解像度',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
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
            const SizedBox(height: 16),

            // Frame Rate
            const Text(
              'フレームレート',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
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
            const SizedBox(height: 16),

            // Timeline Duration
            const Text(
              'タイムライン長さ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
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
                DropdownMenuItem(value: 1, child: Text('1分')),
                DropdownMenuItem(value: 2, child: Text('2分')),
                DropdownMenuItem(value: 3, child: Text('3分')),
                DropdownMenuItem(value: 5, child: Text('5分')),
                DropdownMenuItem(value: 10, child: Text('10分')),
                DropdownMenuItem(value: -1, child: Text('無制限')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedDurationMinutes = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('プロジェクト名を入力してください')),
              );
              return;
            }

            Navigator.pop(context, {
              'name': _nameController.text.trim(),
              'resolution': _selectedResolution,
              'frameRate': _selectedFPS,
              'maxDuration': _selectedDurationMinutes == -1
                  ? null
                  : Duration(minutes: _selectedDurationMinutes),
            });
          },
          child: const Text('保存'),
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
