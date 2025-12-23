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
    return matchesShortcut(event, LogicalKeyboardKey.keyZ, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyZ, ctrl: true);
  }

  bool isRedo(KeyEvent event) {
    return matchesShortcut(
          event,
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ) ||
        matchesShortcut(
          event,
          LogicalKeyboardKey.keyZ,
          ctrl: true,
          shift: true,
        );
  }

  bool isSave(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyS, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyS, ctrl: true);
  }

  bool isNew(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyN, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyN, ctrl: true);
  }

  bool isOpen(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyO, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyO, ctrl: true);
  }

  bool isCut(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyX, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyX, ctrl: true);
  }

  bool isCopy(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyC, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyC, ctrl: true);
  }

  bool isPaste(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyV, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyV, ctrl: true);
  }

  bool isDelete(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace);
  }

  bool isSelectAll(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyA, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyA, ctrl: true);
  }

  bool isPlay(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space;
  }

  bool isSplitClip(KeyEvent event) {
    return matchesShortcut(
          event,
          LogicalKeyboardKey.keyS,
          meta: true,
          shift: true,
        ) ||
        matchesShortcut(
          event,
          LogicalKeyboardKey.keyS,
          ctrl: true,
          shift: true,
        );
  }

  bool isZoomIn(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.equal, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.equal, ctrl: true);
  }

  bool isZoomOut(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.minus, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.minus, ctrl: true);
  }

  bool isExport(KeyEvent event) {
    return matchesShortcut(event, LogicalKeyboardKey.keyE, meta: true) ||
        matchesShortcut(event, LogicalKeyboardKey.keyE, ctrl: true);
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
