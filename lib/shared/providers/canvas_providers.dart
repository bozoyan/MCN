// 职责: 装配画布服务、内容流、场次引用投影与 AI 活动广播。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/canvas_ai_activity.dart
//   lib/shared/providers/screenplay_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../models/canvas_ai_activity.dart';
import '../models/canvas_scene_reference.dart';
import '../services/canvas_service.dart';
import 'novel_providers.dart';
import 'screenplay_providers.dart';

part 'canvas_providers.g.dart';

/// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
///
/// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
/// entityRelations/foreshadowings 等同级 content provider 一致——canvas
/// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。
@riverpod
CanvasService canvasService(Ref ref, String databasePath) {
  // NovelContentDatabase 的生命周期由 keepAlive 的
  // novelContentDatabaseProvider 管理(引用计数 + close),此处不重复 onDispose
  // close,避免双关(参见 novelContentServiceProvider 同款模式)。
  final database = ref.watch(novelContentDatabaseProvider(databasePath));
  return CanvasService(database);
}

/// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。
@riverpod
Stream<List<CanvasEntry>> canvases(Ref ref, String databasePath) {
  return ref.watch(canvasServiceProvider(databasePath)).watchCanvases();
}

/// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。
@riverpod
Future<Map<String, CanvasSceneReference>> canvasSceneReferences(
  Ref ref,
  String databasePath,
) async {
  final root = await ref.watch(screenplayRootProvider(databasePath).future);
  if (root == null) {
    return const {};
  }
  final seasonsFuture = ref.watch(
    screenplaySeasonsProvider(databasePath, root.id).future,
  );
  final episodesFuture = ref.watch(
    screenplayEpisodesOfScreenplayProvider(databasePath, root.id).future,
  );
  final scenesFuture = ref.watch(
    screenplayScenesOfScreenplayProvider(databasePath, root.id).future,
  );
  final seasons = {for (final season in await seasonsFuture) season.id: season};
  final episodes = await episodesFuture;
  final scenes = await scenesFuture;
  return Map.unmodifiable({
    for (final episode in episodes)
      if (seasons.containsKey(episode.seasonId))
        for (final scene in scenes[episode.id] ?? const [])
          scene.id: CanvasSceneReference(
            scene: scene,
            episode: episode,
            season: seasons[episode.seasonId]!,
          ),
  });
}

/// 画布页消费一条 AI 活动、并在演完这一步时完成的回调。
typedef CanvasAiPacer = Future<void> Function(CanvasAiActivity activity);

/// AI 画布操作的广播点。
///
/// canvas 工具写库成功后经注入的 reporter 回调打到这里,画布 UI 据此跟随镜头、
/// 渲染「AI 正在做什么」状态条。DB stream 只能告诉 UI「内容变了」,分不出
/// 是 AI 写的还是用户拖的,也没有语义标签 —— 这条通道补的正是这两点。
///
/// keepAlive:AI 可能在画布页尚未 rebuild 时就写完一批节点,provider 被回收会丢事件。
///
/// state 只保留最新一条,供宿主做「新建/打开画布」这类导航;画布页的分镜导演
/// 走 [attachPacer] 直连 —— 批量处理同一帧连报多条时,watch state 只看得到最后
/// 一条,前面的 add_node 会丢,节点就绕过揭示直接冒出来。
@Riverpod(keepAlive: true)
class CanvasAiActivityNotifier extends _$CanvasAiActivityNotifier {
  int _seq = 0;
  final Map<String, CanvasAiPacer> _pacers = <String, CanvasAiPacer>{};

  @override
  CanvasAiActivity? build() => null;

  /// 上报一次操作,返回画布页演完这一步的时刻(画布页没开时立即完成)。
  ///
  /// seq 由本 notifier 统一分配,调用方不需要维护。工具 await 返回值实现背压,
  /// 单次等待上限与取消放行由工具侧负责。
  Future<void> report(CanvasAiActivity activity) {
    _seq += 1;
    final sequenced = activity.copyWithSeq(_seq);
    state = sequenced;
    return _pacers[activity.canvasId]?.call(sequenced) ?? Future<void>.value();
  }

  /// 画布页挂上自己的节拍器。同一画布后挂的覆盖先挂的。
  void attachPacer(String canvasId, CanvasAiPacer pacer) {
    _pacers[canvasId] = pacer;
  }

  /// 摘掉节拍器;只摘自己挂的那个,避免新页面先挂、旧页面后卸时被误摘。
  void detachPacer(String canvasId, CanvasAiPacer pacer) {
    if (_pacers[canvasId] == pacer) {
      _pacers.remove(canvasId);
    }
  }

  /// 画布页卸载时清空,避免下次打开画布看到上一次的残留状态条。
  void clear() {
    state = null;
  }
}

/// 监听某张画布的节点 + 边合并快照(任一变化即重发)。
///
/// family 键为 `(canvasId, databasePath)` 记录,内部转调
/// [CanvasService.watchCanvasContent]。供 `CanvasBoard` 同步 flow controller。
/// 用 plain `StreamProvider.family`(非 codegen)避免改动生成文件。
final canvasContentStreamProvider =
    StreamProvider.family<
      ({List<CanvasNode> nodes, List<CanvasEdge> edges}),
      ({String canvasId, String databasePath})
    >((ref, key) {
      final service = ref.watch(canvasServiceProvider(key.databasePath));
      return service.watchCanvasContent(key.canvasId);
    });

/// 监听单张画布的元数据(名称等)。供画布区域展示画布名。
///
/// 用 plain `StreamProvider.family`(非 codegen)避免改动生成文件。
final canvasEntryProvider =
    StreamProvider.family<
      CanvasEntry?,
      ({String canvasId, String databasePath})
    >((ref, key) {
      final database = ref.watch(
        novelContentDatabaseProvider(key.databasePath),
      );
      return database.canvasDao.watchCanvasById(key.canvasId);
    });

/// 检测某张画布上引用已失效(资源被删)的节点 id 集合。
///
/// 依赖画布内容和场次投影，源场次与父级变化即重算。供 `CanvasBoard`
/// 渲染灰态与顶栏「清理失效」按钮计数。用 plain `FutureProvider.family`
/// (非 codegen)避免改动生成文件。
final canvasInvalidNodeIdsProvider =
    FutureProvider.family<
      Set<String>,
      ({String canvasId, String databasePath})
    >((ref, key) async {
      final content = await ref.watch(canvasContentStreamProvider(key).future);
      final service = ref.watch(canvasServiceProvider(key.databasePath));
      final scenes =
          content.nodes.any(
            (node) => node.refType == canvasNodeRefTypeScreenplayScene,
          )
          ? await ref.watch(
              canvasSceneReferencesProvider(key.databasePath).future,
            )
          : const <String, CanvasSceneReference>{};
      final invalid = <String>{};
      for (final node in content.nodes) {
        if (node.type != canvasNodeTypeReference) {
          continue;
        }
        final refType = node.refType;
        final refId = node.refId;
        if (refType == null || refId == null) {
          continue;
        }
        final exists = refType == canvasNodeRefTypeScreenplayScene
            ? scenes.containsKey(refId)
            : await service.referenceExists(refType, refId);
        if (!exists) {
          invalid.add(node.id);
        }
      }
      return invalid;
    });
