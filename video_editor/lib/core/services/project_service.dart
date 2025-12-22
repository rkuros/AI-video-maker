import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:video_editor/core/models/models.dart';

/// Service for managing video editing projects
class ProjectService {
  /// Save a project to a file
  Future<void> saveProject(Project project, String filePath) async {
    try {
      final file = File(filePath);

      // Ensure directory exists
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Convert project to JSON
      final jsonData = project.toJson();
      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);

      // Write to file
      await file.writeAsString(jsonString);
    } catch (e) {
      throw Exception('Failed to save project: $e');
    }
  }

  /// Load a project from a file
  Future<Project> loadProject(String filePath) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        throw Exception('Project file not found: $filePath');
      }

      // Read file contents
      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // Parse project from JSON
      return Project.fromJson(jsonData);
    } catch (e) {
      throw Exception('Failed to load project: $e');
    }
  }

  /// Check if a project file exists
  Future<bool> projectExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  /// Get the default project directory
  Future<String> getDefaultProjectDirectory() async {
    // Get user's home directory
    final homeDir = Platform.environment['HOME'] ??
                   Platform.environment['USERPROFILE'] ??
                   '/tmp';

    final projectsDir = path.join(homeDir, 'VideoEditorProjects');

    // Create directory if it doesn't exist
    final directory = Directory(projectsDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return projectsDir;
  }

  /// Generate a default file path for a new project
  Future<String> getDefaultFilePath(String projectName) async {
    final projectsDir = await getDefaultProjectDirectory();

    // Sanitize project name for file system
    final sanitizedName = projectName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();

    final fileName = '$sanitizedName.vedproj';
    return path.join(projectsDir, fileName);
  }

  /// List all projects in the default directory
  Future<List<String>> listProjects() async {
    final projectsDir = await getDefaultProjectDirectory();
    final directory = Directory(projectsDir);

    if (!await directory.exists()) {
      return [];
    }

    final entities = await directory.list().toList();
    final projectFiles = entities
        .whereType<File>()
        .where((file) => file.path.endsWith('.vedproj'))
        .map((file) => file.path)
        .toList();

    return projectFiles;
  }

  /// Delete a project file
  Future<void> deleteProject(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Create a backup of a project file
  Future<String> backupProject(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('Project file not found');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '$filePath.backup-$timestamp';

    await file.copy(backupPath);
    return backupPath;
  }

  /// Get project info without loading the entire project
  Future<Map<String, dynamic>> getProjectInfo(String filePath) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      return {
        'name': jsonData['name'],
        'createdAt': jsonData['createdAt'],
        'updatedAt': jsonData['updatedAt'],
        'filePath': filePath,
      };
    } catch (e) {
      throw Exception('Failed to get project info: $e');
    }
  }
}
