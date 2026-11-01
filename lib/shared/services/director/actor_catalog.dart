// 职责: 预加载角色目录，合并初始候选并保留可重试的加载状态。
// 关联文件:
//   lib/shared/models/director/actor_catalog.dart
//   lib/shared/widgets/director/workspace.dart
//   lib/shared/widgets/director/panels/actors.dart
import 'package:flutter/foundation.dart';
import '../../logger/app_logger.dart';
import '../../models/director/actor_catalog.dart';

final _log = AppLogger.forModule('DirectorActorCatalog');

class DirectorActorCatalogController extends ChangeNotifier {
  DirectorActorCatalogController(this.source)
    : actors = List.unmodifiable(source.initialActors ?? const []);

  final DirectorActorCatalog source;
  List<DirectorActor> actors;
  bool loading = false;
  bool failed = false;
  bool _disposed = false;

  Future<void> load() async {
    final loader = source.load;
    if (loader == null || loading || _disposed) {
      return;
    }
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final loaded = await loader();
      final merged = <String, DirectorActor>{};
      for (final actor in [...?source.initialActors, ...loaded]) {
        if (actor.id.trim().isEmpty || actor.name.trim().isEmpty) {
          throw ArgumentError('Actor catalog requires nonempty IDs and names');
        }
        merged[actor.id] = actor;
      }
      if (!_disposed) {
        actors = List.unmodifiable(merged.values);
      }
    } catch (error, stack) {
      _log.error(
        'Director actor catalog load failed',
        error: error,
        stackTrace: stack,
      );
      if (!_disposed) {
        failed = true;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
