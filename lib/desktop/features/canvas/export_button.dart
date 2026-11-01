// 职责: 等待画布编辑保存后采集快照，直接编码 ZIP 并提供桌面保存反馈。
// 关联文件:
//   lib/desktop/features/canvas/edit_session.dart
//   lib/desktop/features/canvas/export_preview.dart
//   lib/shared/services/canvas_export/orchestrator.dart
//   lib/shared/services/canvas_export/save.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/file-access.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/canvas_export.dart';
import '../../../shared/models/canvas_scene_reference.dart';
import '../../../shared/providers/canvas_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/canvas_export/orchestrator.dart';
import '../../../shared/services/canvas_export/save.dart';
import '../../../shared/theme/theme.dart';
import 'edit_session.dart';
import 'export_preview.dart';
import 'widgets/floating_cluster.dart';

final _log = AppLogger.forModule('CanvasExportButton');
typedef CanvasExportSource = ({
  String canvasId,
  String databasePath,
  String workId,
  String contentKind,
});

class CanvasExportButton extends HookConsumerWidget {
  const CanvasExportButton({
    super.key,
    required this.source,
    required this.session,
    this.saveArtifact = saveCanvasExport,
    this.onBlocked,
  });
  final CanvasExportSource source;
  final CanvasEditSession session;
  final Future<CanvasExportSaveResult> Function(CanvasExportArtifact)
  saveArtifact;
  final VoidCallback? onBlocked;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);
    useListenable(session);
    final nodes = ref
        .watch(
          canvasContentStreamProvider((
            canvasId: source.canvasId,
            databasePath: source.databasePath,
          )),
        )
        .asData
        ?.value
        .nodes;
    // 预览卡片的灰态与场次标题取画布正在用的同一份值。
    final invalidNodeIds =
        ref
            .watch(
              canvasInvalidNodeIdsProvider((
                canvasId: source.canvasId,
                databasePath: source.databasePath,
              )),
            )
            .asData
            ?.value ??
        const <String>{};
    final scenes =
        ref.watch(canvasSceneReferencesProvider(source.databasePath)).value ??
        const <String, CanvasSceneReference>{};
    Future<void> export() async {
      if (onBlocked != null) {
        onBlocked!();
        return;
      }
      busy.value = true;
      try {
        final orchestrator = CanvasExportOrchestrator();
        final container = ProviderScope.containerOf(context, listen: false);
        final snapshot = await session.runExclusive(() async {
          FocusManager.instance.primaryFocus?.unfocus();
          final lease = container.listen(
            novelContentDatabaseProvider(source.databasePath),
            (_, _) {},
          );
          try {
            return await orchestrator.snapshot(
              database: lease.read(),
              canvasId: source.canvasId,
              workId: source.workId,
              contentKind: source.contentKind,
            );
          } finally {
            lease.close();
          }
        });
        if (!context.mounted) {
          return;
        }
        final preview = await buildCanvasExportPreview(
          context,
          snapshot: snapshot,
          invalidNodeIds: invalidNodeIds,
          scenes: scenes,
        );
        if (!context.mounted) {
          return;
        }
        // 编码只持有快照与预览纯值；画布此时可继续编辑。
        final artifact = await orchestrator.encode(
          snapshot,
          CanvasExportFormat.zip,
          preview: preview,
        );
        if (!context.mounted) {
          return;
        }
        final result = await saveArtifact(artifact);
        if (!context.mounted ||
            result.status == CanvasExportSaveStatus.cancelled) {
          return;
        }
        final key = result.status == CanvasExportSaveStatus.saved
            ? LocaleKeys.canvasExportSaved
            : result.mayHavePartialFile
            ? LocaleKeys.canvasExportPartialFile
            : LocaleKeys.canvasExportFailed;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t(key))));
      } catch (error, stackTrace) {
        _log.error(
          'export result=failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          final key = switch (error) {
            CanvasEditSessionException(code: 'input_composing') =>
              LocaleKeys.canvasFinishInput,
            CanvasEditSessionException(code: 'save_failed') =>
              LocaleKeys.canvasExportSaveEditsFailed,
            _ => LocaleKeys.canvasExportFailed,
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.t(key))));
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    return CanvasFloatingButton(
      icon: RevericIcons.download,
      tooltip: context.t(
        busy.value ? LocaleKeys.canvasExporting : LocaleKeys.canvasExport,
      ),
      onTap: busy.value || session.busy || nodes == null || nodes.isEmpty
          ? null
          : export,
    );
  }
}
