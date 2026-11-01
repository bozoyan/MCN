// 职责: 在节点与全屏间共享全景视角，合并操作并串行防抖保存。
// 关联文件:
//   lib/shared/providers/production_panorama.dart
//   lib/shared/models/production/panorama.dart
//   lib/shared/widgets/production/panorama/viewer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../logger/app_logger.dart';
import '../../../models/production/panorama.dart';

final _log = AppLogger.forModule('Panorama');

class PanoramaController extends ChangeNotifier {
  PanoramaController({required PanoramaView initial, required this.save})
    : _view = initial;
  final Future<void> Function(PanoramaView) save;
  PanoramaView _view;
  PanoramaView get view => _view;
  bool grid = false;
  Object? error;
  Timer? _timer;
  Future<void> _writes = Future.value();
  int _revision = 0;
  bool _dirty = false, _interacting = false, _disposed = false;
  void restore(PanoramaView view) {
    if (!_dirty && !_interacting && view != _view) {
      _view = view;
      notifyListeners();
    }
  }

  void begin() {
    _interacting = true;
    _timer?.cancel();
  }

  void update(PanoramaView view) {
    view.validate();
    if (view == _view) {
      return;
    }
    _view = view;
    _revision++;
    _dirty = true;
    notifyListeners();
  }

  void end() {
    _interacting = false;
    _schedule();
  }

  void set(PanoramaView view) {
    update(view);
    _schedule();
  }

  void reset() => set(const PanoramaView());
  void toggleGrid() {
    grid = !grid;
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    if (!_dirty) {
      return _writes;
    }
    final snapshot = _view;
    final revision = _revision;
    _writes = _writes.then((_) async {
      try {
        await save(snapshot);
        // 相同视角也可能来自后续操作；只有当前编辑版本落库才可清 dirty。
        if (_revision == revision) {
          _dirty = false;
        }
        error = null;
      } catch (exception, stack) {
        error = exception;
        _log.error('save view failed', error: exception, stackTrace: stack);
      }
      if (!_disposed) {
        notifyListeners();
      }
    });
    return _writes;
  }

  /// 退出预览前停止延迟保存，避免旧视角在退出后重新创建 panorama 键。
  Future<void> stopSaving() async {
    _timer?.cancel();
    await _writes;
    _dirty = false;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flush());
    _timer?.cancel();
    super.dispose();
  }
}
