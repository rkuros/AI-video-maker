import 'package:flutter/services.dart';

/// Service for managing keyboard shortcuts
class KeyboardShortcutService {
  /// Check if a key event matches a specific shortcut
  bool matchesShortcut(
    KeyEvent event,
    LogicalKeyboardKey key, {
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
  }) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != key) return false;

    final hasCtrl = HardwareKeyboard.instance.isControlPressed;
    final hasShift = HardwareKeyboard.instance.isShiftPressed;
    final hasAlt = HardwareKeyboard.instance.isAltPressed;
    final hasMeta = HardwareKeyboard.instance.isMetaPressed;

    return hasCtrl == ctrl &&
        hasShift == shift &&
        hasAlt == alt &&
        hasMeta == meta;
  }

  /// Common shortcuts
  bool isUndo(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyZ, meta: true);
  }

  bool isRedo(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyZ, meta: true, shift: true);
  }

  bool isSave(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyS, meta: true);
  }

  bool isNew(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyN, meta: true);
  }

  bool isOpen(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyO, meta: true);
  }

  bool isCut(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyX, meta: true);
  }

  bool isCopy(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyC, meta: true);
  }

  bool isPaste(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyV, meta: true);
  }

  bool isDelete(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace);
  }

  bool isSelectAll(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyA, meta: true);
  }

  bool isPlay(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space;
  }

  bool isSplitClip(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyS, meta: true, shift: true);
  }

  bool isZoomIn(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.equal, meta: true);
  }

  bool isZoomOut(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.minus, meta: true);
  }

  bool isExport(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyE, meta: true);
  }

  /// Get shortcut description for display
  String getShortcutDescription(String action) {
    switch (action) {
      case 'undo':
        return 'Cmd+Z';
      case 'redo':
        return 'Cmd+Shift+Z';
      case 'save':
        return 'Cmd+S';
      case 'new':
        return 'Cmd+N';
      case 'open':
        return 'Cmd+O';
      case 'cut':
        return 'Cmd+X';
      case 'copy':
        return 'Cmd+C';
      case 'paste':
        return 'Cmd+V';
      case 'delete':
        return 'Delete';
      case 'selectAll':
        return 'Cmd+A';
      case 'play':
        return 'Space';
      case 'splitClip':
        return 'Cmd+Shift+S';
      case 'zoomIn':
        return 'Cmd+=';
      case 'zoomOut':
        return 'Cmd+-';
      case 'export':
        return 'Cmd+E';
      default:
        return '';
    }
  }
}
