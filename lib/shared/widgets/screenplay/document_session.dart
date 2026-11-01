// 职责: 管理当前剧本文档的保存基线、串行队列与按节点通知，保留保存期间的新草稿。
// 关联文件:
//   lib/shared/models/screenplay_document.dart
//   lib/shared/widgets/screenplay/editing_controller.dart
//   lib/shared/services/document_save_coordinator.dart
//   lib/shared/services/screenplay_edit_orchestrator.dart

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import '../../database/novel_content_database.dart';
import '../../models/screenplay_document.dart';
import '../../models/screenplay_editing.dart';
import '../../models/screenplay_element.dart';
import '../../services/document_save_coordinator.dart';
import '../../services/screenplay_edit_orchestrator.dart';
import '../../services/screenplay_service.dart';
import '../../services/working_overlay.dart';
import 'editing_controller.dart';

class ScreenplayDocumentSession {
  ScreenplayDocumentSession(
    ScreenplayDocument initial, {
    required NovelContentDatabase database,
    required ScreenplayService service,
    required WorkingOverlayService overlay,
  }) : _service = service,
       baseline = initial,
       controller = ScreenplayEditingController.forDocument(
         initial,
         ScreenplayElementKeys(),
       ) {
    queue = DocumentSaveCoordinator<ScreenplayDocument>(
      save: (target) async {
        final result = await ScreenplayEditOrchestrator().save(
          database: database,
          service: service,
          overlay: overlay,
          baseline: baseline,
          target: target,
        );
        baseline = result.document;
        if (!_disposed) {
          controller.acknowledgeDocumentIds(result.sceneIds, result.elementIds);
          final submitted = target.remapIdentities(
            result.sceneIds,
            result.elementIds,
          );
          final rebased = controller.screenplay!.rebaseUnchanged(
            submitted,
            result.document,
          );
          queue.rebasePending(rebased);
          // 保存确认本身不清除撤销；只有同期外部业务变化需要作废旧历史。
          if (!sameScreenplayElements(
                submitted.elements,
                result.document.elements,
              ) ||
              submitted.scenes.entries.any(
                (e) => !e.value.sameAs(result.document.scenes[e.key]),
              )) {
            controller.acceptExternalDocument(rebased);
          } else {
            // Even an unchanged save refreshes tombstone reservations for the
            // next synchronous draft command without clearing undo history.
            controller.screenplay = rebased;
          }
          statisticsPending.value = result.statisticsPending;
          _lastSavedAt = DateTime.now();
        }
      },
    );
    controller.onEdited = (_) => queue.schedule(controller.screenplay!);
    controller.addListener(_refreshNodes);
    _refreshNodes();
  }
  final ScreenplayService _service;
  ScreenplayDocument baseline;
  final ScreenplayEditingController controller;
  late final DocumentSaveCoordinator<ScreenplayDocument> queue;
  final structure = ValueNotifier<List<String>>([]);
  final statisticsPending = ValueNotifier(false);
  DateTime? _lastSavedAt;
  DateTime? get lastSavedAt => _lastSavedAt;
  final Map<String, ValueNotifier<ScreenplayElement>> nodes = {};
  final Map<String, int> indices = {};
  final Map<String, VoidCallback> headingEditors = {};
  List<String> episodeSceneOrder = [];

  int sceneNumber(String id) {
    final document = controller.screenplay!;
    if (document.fullEpisode || episodeSceneOrder.isEmpty) {
      return document.sceneOrder.indexOf(id) + 1;
    }
    final scope = {...baseline.scenes.keys, ...document.scenes.keys};
    var insertion = episodeSceneOrder.indexWhere(scope.contains);
    if (insertion < 0) {
      insertion = episodeSceneOrder.indexOf(baseline.nextSceneId ?? '');
      if (insertion < 0 && baseline.previousSceneId != null) {
        final preceding = episodeSceneOrder.indexOf(baseline.previousSceneId!);
        if (preceding >= 0) {
          insertion = preceding + 1;
        }
      }
    }
    final order = episodeSceneOrder.where((id) => !scope.contains(id)).toList();
    order.insertAll(
      insertion < 0 ? order.length : insertion.clamp(0, order.length),
      document.sceneOrder,
    );
    return order.indexOf(id) + 1;
  }

  Map<String, ScreenplayDocumentScene> _lastScenes = {};
  bool _disposed = false;

  void _refreshNodes() {
    if (_disposed) {
      return;
    }
    final ids = <String>[];
    indices.clear();
    for (final (index, element) in controller.value.indexed) {
      final id = element.id!;
      ids.add(id);
      indices[id] = index;
      final notifier = nodes.putIfAbsent(id, () => ValueNotifier(element));
      final metadataChanged =
          element.isHeading &&
          !(_lastScenes[element.sceneId]?.sameAs(
                controller.screenplay!.scenes[element.sceneId],
              ) ??
              false);
      if (!sameScreenplayElements([notifier.value], [element]) ||
          metadataChanged) {
        notifier.value = metadataChanged ? element.copyWith() : element;
      }
    }
    _lastScenes = controller.screenplay!.scenes;
    if (!const ListEquality<String>().equals(ids, structure.value)) {
      structure.value = ids;
    }
  }

  void acceptExternal(ScreenplayDocument incoming) {
    if (_disposed ||
        queue.isDirty ||
        queue.isSaving ||
        controller.isComposing) {
      return;
    }
    if (!baseline.fullEpisode) {
      final ids = baseline.scenes.keys.toSet();
      final order = incoming.sceneOrder;
      final positions = [
        for (var i = 0; i < order.length; i++)
          if (ids.contains(order[i])) i,
      ];
      incoming = ScreenplayDocument(
        episodeId: incoming.episodeId,
        screenplayId: incoming.screenplayId,
        fullEpisode: false,
        reservedIds: incoming.reservedIds,
        previousSceneId: positions.isEmpty
            ? baseline.previousSceneId
            : positions.first > 0
            ? order[positions.first - 1]
            : null,
        nextSceneId: positions.isEmpty
            ? baseline.nextSceneId
            : positions.last + 1 < order.length
            ? order[positions.last + 1]
            : null,
        elements: incoming.elements.where((e) => ids.contains(e.sceneId)),
        scenes: {for (final id in ids) id: ?incoming.scenes[id]},
        evidenceVersions: {
          for (final entry in incoming.evidenceVersions.entries)
            if (ids.contains(incoming.evidence[entry.key]))
              entry.key: entry.value,
        },
        evidence: Map.fromEntries(
          incoming.evidence.entries.where((e) => ids.contains(e.value)),
        ),
      );
    }
    baseline = incoming;
    controller.acceptExternalDocument(incoming);
  }

  Future<void> flush() => queue.flush();

  Future<void> reload() async {
    if (queue.isSaving) {
      return;
    }
    final revision = controller.revision;
    final current = await _service.readDocument(baseline.episodeId);
    if (_disposed || queue.isSaving || revision != controller.revision) {
      return;
    }
    queue.discardPending();
    acceptExternal(current);
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_refreshNodes);
    controller.dispose();
    headingEditors.clear();
    queue.dispose();
    structure.dispose();
    statisticsPending.dispose();
    for (final value in nodes.values) {
      value.dispose();
    }
  }
}
