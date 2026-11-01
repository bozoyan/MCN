// 职责: 串行保存条目编辑草稿，保留失败改动并安全冲刷退出前的最新输入。
// 关联文件:
//   lib/mobile/pages/entry_editor_page.dart
//   lib/mobile/pages/location_editor_save.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/logger/app_logger.dart';

typedef EntryEditorValues = ({String title, String content, String category});

final _log = AppLogger.forModule('EntryEditorSave');

class EntryEditorSaveController extends ChangeNotifier {
  EntryEditorSaveController({
    required this.onSave,
    required EntryEditorValues initialValues,
  }) : _draft = initialValues,
       _saved = initialValues;

  Future<void> Function(String title, String content, String category) onSave;
  EntryEditorValues _draft;
  EntryEditorValues _saved;
  Timer? _timer;
  Future<bool>? _pending;
  bool _disposed = false;
  bool failed = false;
  DateTime? savedAt;
  bool get isDirty => _draft != _saved;
  bool get isSaving => _pending != null;

  void update(EntryEditorValues draft) {
    if (_disposed || draft == _draft) {
      return;
    }
    final wasDirty = isDirty;
    final hadFailure = failed;
    _draft = draft;
    failed = false;
    _timer?.cancel();
    if (isDirty) {
      _timer = Timer(
        const Duration(milliseconds: 800),
        () => unawaited(flush()),
      );
    }
    if (wasDirty != isDirty || hadFailure) {
      notifyListeners();
    }
  }

  Future<bool> flush() {
    _timer?.cancel();
    if (_pending case final pending?) {
      return pending;
    }
    if (!isDirty) {
      return Future.value(true);
    }
    failed = false;
    final run = _saveLatest().whenComplete(() {
      _pending = null;
      if (!_disposed) {
        notifyListeners();
      }
    });
    _pending = run;
    if (!_disposed) {
      notifyListeners();
    }
    return run;
  }

  Future<bool> _saveLatest() async {
    while (isDirty) {
      final saving = _draft;
      try {
        await onSave(saving.title, saving.content, saving.category);
        _saved = saving;
        savedAt = DateTime.now();
      } catch (error, stackTrace) {
        _log.error('Entry save failed', error: error, stackTrace: stackTrace);
        if (_draft != saving) {
          continue;
        }
        failed = true;
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    // 保存只持有值快照；即使页面已卸载，也不会读取 controller 或通知 UI。
    unawaited(flush());
    super.dispose();
  }
}
