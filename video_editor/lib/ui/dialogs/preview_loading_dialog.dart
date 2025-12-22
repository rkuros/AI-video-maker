import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_editor/core/engines/export_engine.dart';

/// Dialog that shows progress while generating timeline preview
class PreviewLoadingDialog extends StatefulWidget {
  final Future<void> Function(Function(ExportProgress) onProgress) generatePreview;

  const PreviewLoadingDialog({
    super.key,
    required this.generatePreview,
  });

  @override
  State<PreviewLoadingDialog> createState() => _PreviewLoadingDialogState();

  /// Show the dialog and start generating preview
  static Future<bool> show(
    BuildContext context,
    Future<void> Function(Function(ExportProgress) onProgress) generatePreview,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PreviewLoadingDialog(
        generatePreview: generatePreview,
      ),
    );
    return result ?? false;
  }
}

class _PreviewLoadingDialogState extends State<PreviewLoadingDialog> {
  double _progress = 0.0;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    // Delay to avoid modifying provider during widget build
    Future.microtask(() => _startGeneration());
  }

  Future<void> _startGeneration() async {
    try {
      await widget.generatePreview((progress) {
        if (mounted) {
          setState(() {
            _progress = progress.progress;
          });
        }
      });

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('プレビュー生成中'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error == null) ...[
            const Text('タイムラインのプレビューを生成しています。しばらくお待ちください。'),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ] else ...[
            Text(
              'プレビュー生成に失敗しました:',
              style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _copied
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _error!));
                            if (!mounted) return;
                            setState(() {
                              _copied = true;
                            });
                          },
                    child: Text(_copied ? 'コピーしました' : 'エラーをコピー'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('閉じる'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
