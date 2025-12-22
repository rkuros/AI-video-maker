import 'package:flutter/material.dart';

/// Dialog showing keyboard shortcuts
class KeyboardShortcutsHelp extends StatelessWidget {
  const KeyboardShortcutsHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection('Project', [
                      _buildShortcut('Cmd+N', 'New Project'),
                      _buildShortcut('Cmd+O', 'Open Project'),
                      _buildShortcut('Cmd+S', 'Save Project'),
                      _buildShortcut('Cmd+E', 'Export Video'),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Editing', [
                      _buildShortcut('Cmd+Z', 'Undo'),
                      _buildShortcut('Cmd+Shift+Z', 'Redo'),
                      _buildShortcut('Cmd+X', 'Cut'),
                      _buildShortcut('Cmd+C', 'Copy'),
                      _buildShortcut('Cmd+V', 'Paste'),
                      _buildShortcut('Delete/Backspace', 'Delete Selection'),
                      _buildShortcut('Cmd+A', 'Select All'),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Playback', [
                      _buildShortcut('Space', 'Play/Pause'),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Timeline', [
                      _buildShortcut('Cmd+Shift+S', 'Split Clip'),
                      _buildShortcut('Cmd+=', 'Zoom In'),
                      _buildShortcut('Cmd+-', 'Zoom Out'),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts,
      ],
    );
  }

  Widget _buildShortcut(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey[700]!),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            description,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
