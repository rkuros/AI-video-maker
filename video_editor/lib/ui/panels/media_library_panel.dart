import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:io';
import 'package:video_editor/core/logic/media_library_provider.dart';
import 'package:video_editor/core/logic/preview_provider.dart';
import 'package:video_editor/core/models/enums.dart';
import 'package:video_editor/core/models/media_item.dart';
import 'package:video_editor/utils/file_validator.dart';

class MediaLibraryPanel extends ConsumerStatefulWidget {
  const MediaLibraryPanel({super.key});

  @override
  ConsumerState<MediaLibraryPanel> createState() => _MediaLibraryPanelState();
}

class _MediaLibraryPanelState extends ConsumerState<MediaLibraryPanel> {
  MediaType? _filterType;
  String _searchQuery = '';
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final mediaItems = ref.watch(mediaLibraryProvider);
    final counts = ref.watch(mediaLibraryCountsProvider);

    // Filter items based on type filter and search query
    var filteredItems = _filterType == null
        ? mediaItems
        : mediaItems.where((item) => item.type == _filterType).toList();

    if (_searchQuery.isNotEmpty) {
      filteredItems = filteredItems
          .where((item) =>
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        final filePaths = details.files
            .map((file) => file.path)
            .where((path) => FileValidator.isSupportedFile(path))
            .toList();
        if (filePaths.isNotEmpty) {
          await _importFilePaths(filePaths);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No supported files found')),
          );
        }
      },
      child: Stack(
        children: [
          Container(
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _buildHeader(),
                const Divider(height: 1),

                // Filter tabs
                _buildFilterTabs(counts),

                // Search bar
                _buildSearchBar(),

                const Divider(height: 1),

                // Media items grid or empty state
                Expanded(
                  child: filteredItems.isEmpty
                      ? _buildEmptyState()
                      : _buildMediaGrid(filteredItems),
                ),
              ],
            ),
          ),
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: Colors.blue.withValues(alpha: 0.15),
                child: Center(
                  child: Text(
                    'Drop files to import',
                    style: TextStyle(
                      color: Colors.blue[200],
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Media Library',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _importFiles,
            tooltip: 'Import Files',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(Map<MediaType, int> counts) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _buildFilterChip(
            label: 'All',
            count: counts.values.fold(0, (sum, count) => sum + count),
            isSelected: _filterType == null,
            onTap: () => setState(() => _filterType = null),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Videos',
            count: counts[MediaType.video] ?? 0,
            isSelected: _filterType == MediaType.video,
            onTap: () => setState(() => _filterType = MediaType.video),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Audio',
            count: counts[MediaType.audio] ?? 0,
            isSelected: _filterType == MediaType.audio,
            onTap: () => setState(() => _filterType = MediaType.audio),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Images',
            count: counts[MediaType.image] ?? 0,
            isSelected: _filterType == MediaType.image,
            onTap: () => setState(() => _filterType = MediaType.image),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search media...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'No media files',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _importFiles,
            icon: const Icon(Icons.add),
            label: const Text('Import Files'),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildMediaCard(items[index]);
      },
    );
  }

  Widget _buildMediaCard(MediaItem item) {
    IconData icon;
    Color iconColor;

    switch (item.type) {
      case MediaType.video:
        icon = Icons.videocam;
        iconColor = Colors.blue;
        break;
      case MediaType.audio:
        icon = Icons.audiotrack;
        iconColor = Colors.orange;
        break;
      case MediaType.image:
        icon = Icons.image;
        iconColor = Colors.green;
        break;
    }

    final fileExists =
        item.filePath.isNotEmpty && File(item.filePath).existsSync();

    return Draggable<MediaItem>(
      data: item,
      maxSimultaneousDrags: fileExists ? null : 0,
      feedback: Material(
        elevation: 4,
        child: Container(
          width: 150,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: Colors.grey[800],
                  child: item.thumbnail != null
                      ? Image.memory(
                          item.thumbnail!,
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          icon,
                          size: 48,
                          color: iconColor,
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(item.duration),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      child: Card(
        child: InkWell(
          onTap: () {
            if (!fileExists) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Missing file: ${item.name}. Please re-link or re-import.'),
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
            // Load video in preview if it's a video
            if (item.type == MediaType.video) {
              ref.read(previewProvider.notifier).loadVideo(item.filePath);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: Colors.grey[800],
                        child: item.thumbnail != null
                            ? Image.memory(
                                item.thumbnail!,
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                icon,
                                size: 48,
                                color: iconColor,
                              ),
                      ),
                    ),
                    if (!fileExists)
                      Positioned(
                        left: 6,
                        top: 6,
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(item.duration),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';

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

  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mov',
        'avi',
        'mkv',
        'mp3',
        'wav',
        'aac',
        'jpg',
        'jpeg',
        'png',
      ],
    );

    if (result != null && result.files.isNotEmpty) {
      final filePaths = result.files
          .where((file) => file.path != null)
          .map((file) => file.path!)
          .toList();
      await _importFilePaths(filePaths);
    }
  }

  Future<void> _importFilePaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return;
    await ref.read(mediaLibraryProvider.notifier).importFiles(filePaths);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${filePaths.length} file(s)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
