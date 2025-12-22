import 'package:video_editor/core/models/enums.dart';

class FileValidator {
  // Supported video formats
  static const supportedVideoExtensions = [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
  ];

  // Supported audio formats
  static const supportedAudioExtensions = [
    '.mp3',
    '.wav',
    '.aac',
  ];

  // Supported image formats
  static const supportedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
  ];

  /// Check if a file is a supported video format
  static bool isVideoFile(String filePath) {
    final extension = _getFileExtension(filePath);
    return supportedVideoExtensions.contains(extension);
  }

  /// Check if a file is a supported audio format
  static bool isAudioFile(String filePath) {
    final extension = _getFileExtension(filePath);
    return supportedAudioExtensions.contains(extension);
  }

  /// Check if a file is a supported image format
  static bool isImageFile(String filePath) {
    final extension = _getFileExtension(filePath);
    return supportedImageExtensions.contains(extension);
  }

  /// Check if a file is supported by the application
  static bool isSupportedFile(String filePath) {
    return isVideoFile(filePath) ||
        isAudioFile(filePath) ||
        isImageFile(filePath);
  }

  /// Get the media type of a file
  static MediaType? getMediaType(String filePath) {
    if (isVideoFile(filePath)) return MediaType.video;
    if (isAudioFile(filePath)) return MediaType.audio;
    if (isImageFile(filePath)) return MediaType.image;
    return null;
  }

  /// Get all supported extensions
  static List<String> get allSupportedExtensions => [
        ...supportedVideoExtensions,
        ...supportedAudioExtensions,
        ...supportedImageExtensions,
      ];

  static String _getFileExtension(String filePath) {
    final lastDotIndex = filePath.lastIndexOf('.');
    if (lastDotIndex == -1) return '';
    return filePath.substring(lastDotIndex).toLowerCase();
  }
}
