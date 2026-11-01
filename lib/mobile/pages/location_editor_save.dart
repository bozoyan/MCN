// 职责: 串行保存移动地点编辑草稿，冲刷最新改动并保留失败状态。
// 关联文件:
//   lib/mobile/pages/location_editor_page.dart
//   lib/shared/services/maps_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../shared/services/maps_service.dart';

typedef LocationEditorValues = ({
  String name,
  String description,
  String type,
  String? parentId,
});

enum LocationEditorSaveFailure { duplicate_name, save_failed }

class LocationEditorSaveController extends ChangeNotifier {
  LocationEditorSaveController({
    required this.service,
    required this.locationId,
    required LocationEditorValues initialValues,
    required this.savedAt,
  }) : _draft = initialValues,
       _saved = initialValues;

  final LocationsService service;
  final String locationId;
  LocationEditorValues _draft;
  LocationEditorValues _saved;
  DateTime? savedAt;
  LocationEditorSaveFailure? failure;
  Timer? _timer;
  Future<bool>? _pending;
  bool _disposed = false;
  bool get isDirty => _draft != _saved;
  bool get isSaving => _pending != null;

  void update(LocationEditorValues draft) {
    if (_disposed || draft == _draft) {
      return;
    }
    final wasDirty = isDirty;
    final hadFailure = failure != null;
    _draft = draft;
    failure = null;
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
    if (_disposed) {
      return Future.value(false);
    }
    if (_pending case final pending?) {
      return pending;
    }
    if (!isDirty) {
      return Future.value(true);
    }
    failure = null;
    late final Future<bool> run;
    run = _saveLatest().whenComplete(() {
      _pending = null;
      if (!_disposed) {
        notifyListeners();
      }
    });
    _pending = run;
    notifyListeners();
    return run;
  }

  Future<bool> _saveLatest() async {
    while (!_disposed && isDirty) {
      final savingDraft = _draft;
      try {
        await service.updateLocation(
          id: locationId,
          name: savingDraft.name,
          description: savingDraft.description,
          type: savingDraft.type,
          parentId: savingDraft.parentId,
          clearParentId: savingDraft.parentId == null,
        );
        _saved = savingDraft;
        savedAt = DateTime.now();
      } catch (error) {
        // 旧请求失败时若输入已变化，继续保存最新草稿，不把旧错误盖到新输入上。
        if (_draft != savingDraft && !_disposed) {
          continue;
        }
        failure = error is DuplicateLocationNameException
            ? LocationEditorSaveFailure.duplicate_name
            : LocationEditorSaveFailure.save_failed;
        return false;
      }
    }
    return !_disposed;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
