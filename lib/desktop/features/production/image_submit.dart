// 职责: 保存图片草稿后直接提交生成，并管理圆形生成 / 取消键的状态。
// 关联文件:
//   lib/shared/providers/production_images.dart
//   lib/shared/services/production/image_generate_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/database/daos/generation_task_dao.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/models/image/extras.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/production_images.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/image_generate_orchestrator.dart';
import '../../../shared/theme/theme.dart';
import 'popover.dart';
import 'support.dart';

class ProductionImageSubmit extends HookConsumerWidget {
  const ProductionImageSubmit({
    super.key,
    required this.service,
    required this.node,
    required this.path,
    required this.save,
    required this.blockedReason,
    this.extras,
  });
  final ProductionCanvasService service;
  final CanvasNode node;
  final String path;
  final Future<bool> Function() save;
  final String? blockedReason;

  /// 当前编辑中的请求级扩展参数;提交时随请求冻结落库。
  final ImageRequestExtras? extras;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(imageTaskServiceProvider);
    final runs = useStream(
      useMemoized(
        () => jobs.watchSource(
          novelId: service.novelId,
          sourceType: 'production_clip',
          sourceId: node.clipId!,
        ),
        [jobs, node.clipId],
      ),
    );
    final active = runs.data?.where(GenerationTaskDao.blocksSource).firstOrNull;
    final preparing = useState(false);
    if (active != null) {
      return ProductionSendButton(
        icon: RevericIcons.stop_rounded,
        tooltip: context.t(LocaleKeys.commonCancel),
        onPressed: () => productionRun(context, () => jobs.cancel(active.id)),
      );
    }
    final blocked = preparing.value
        ? context.t(LocaleKeys.productionGenerateBusy)
        : !runs.hasData
        ? context.t(
            runs.hasError
                ? LocaleKeys.productionFailed
                : LocaleKeys.productionGenerateChecking,
          )
        : blockedReason;
    return ProductionSendButton(
      icon: runs.data?.isNotEmpty ?? false
          ? RevericIcons.arrow_clockwise
          : RevericIcons.arrow_upward_rounded,
      tooltip: blocked ?? context.t(LocaleKeys.productionGenerate),
      onPressed: blocked != null
          ? null
          : () => productionRun(context, () async {
              preparing.value = true;
              try {
                if (!await save() || !context.mounted) {
                  return;
                }
                final preview = await ProductionImageGenerateOrchestrator()
                    .preview(service, node.id, extras: extras);
                if (!context.mounted) {
                  return;
                }
                await jobs.submit(
                  novelId: preview.novelId,
                  sourceType: preview.sourceType,
                  sourceId: preview.sourceId,
                  request: preview.request,
                );
              } finally {
                if (context.mounted) {
                  preparing.value = false;
                }
              }
            }),
    );
  }
}
