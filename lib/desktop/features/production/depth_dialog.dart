// 职责: 展示首次深度模型准备、任务阶段、取消与重试入口。
// 关联文件:
//   lib/shared/providers/depth.dart
//   lib/shared/services/depth/task_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/providers/depth.dart';
import '../../../shared/services/depth/model.dart';
import '../../../shared/services/production/ffmpeg_runner.dart';
import '../../../shared/theme/theme.dart';

final _log = AppLogger.forModule('Depth');

Future<void> showDepthDialog(
  BuildContext context, {
  String? novelId,
  String? nodeId,
}) => showRevericDialog<void>(
  context: context,
  builder: (_) => _DepthDialog(novelId: novelId, nodeId: nodeId),
);

class DepthTaskStatusButton extends ConsumerWidget {
  const DepthTaskStatusButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(depthTaskProvider);
    return ValueListenableBuilder(
      valueListenable: controller.state,
      builder: (context, task, _) => RevericIconButton(
        icon: RevericIcons.layers_outlined,
        tooltip: task == null
            ? context.t(LocaleKeys.productionDepthCapture)
            : '${context.t(LocaleKeys.productionDepthCapture)} · ${context.t('screenplay.production.depth.stage.${task.stage.name}')}',
        onPressed: () => showDepthDialog(context),
      ),
    );
  }
}

class _DepthDialog extends HookConsumerWidget {
  const _DepthDialog({this.novelId, this.nodeId});
  final String? novelId, nodeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(depthTaskProvider);
    final task = useValueListenable(controller.state);
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    useEffect(() {
      var previous = controller.state.value;
      void onTaskChanged() {
        final current = controller.state.value;
        final completed =
            previous?.active == true &&
            current?.stage == DepthStage.complete &&
            previous?.id == current?.id;
        previous = current;
        if (!completed) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted || route == null || !route.isActive) {
            return;
          }
          if (current!.outputNodeId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.t(LocaleKeys.productionDepthLibraryOnly)),
              ),
            );
          }
          if (route.isCurrent) {
            navigator.pop();
          } else {
            navigator.removeRoute(route);
          }
        });
      }

      controller.state.addListener(onTaskChanged);
      return () => controller.state.removeListener(onTaskChanged);
    }, [controller, route, navigator]);
    final check = useMemoized(MediaCancellation.new, [controller]);
    final localError = useState(false);
    void command(Future<void> Function() action) {
      localError.value = false;
      unawaited(
        action().catchError((Object error, StackTrace stack) {
          _log.error('command failed', error: error, stackTrace: stack);
          if (context.mounted) {
            localError.value = true;
          }
        }),
      );
    }

    final ready = useFuture(
      useMemoized(() async {
        await controller.initialize();
        final canStart = controller.state.value?.active != true;
        final installed = await controller.models.isReady(check);
        if (installed &&
            canStart &&
            !check.cancelled &&
            novelId != null &&
            nodeId != null &&
            controller.state.value?.active != true) {
          command(() => controller.start(novelId!, nodeId!));
        }
        return installed;
      }, [controller, check, novelId, nodeId]),
    );
    useEffect(
      () => () {
        unawaited(check.cancel());
      },
      [check],
    );
    final requested = novelId != null && nodeId != null;
    final matches =
        !requested || task?.novelId == novelId && task?.nodeId == nodeId;
    final visible = matches || task?.active == true ? task : null;
    final active = task?.active == true;
    final targetNovel = requested ? novelId : task?.novelId;
    final targetNode = requested ? nodeId : task?.nodeId;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return RevericDialog(
      title: context.t(LocaleKeys.productionDepthCapture),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ready.connectionState != ConnectionState.done && !active)
            const LinearProgressIndicator()
          else if (ready.hasError || localError.value)
            Text(
              context.t(LocaleKeys.productionDepthError),
              style: typo.ui.copyWith(color: colors.error),
            )
          else if (visible != null) ...[
            Text(
              context.t(
                'screenplay.production.depth.stage.${visible.stage.name}',
              ),
            ),
            if (visible.failure != null)
              Text(
                context.t(
                  'screenplay.production.depth.failure.${visible.failure!.name}',
                ),
                style: typo.ui.copyWith(color: colors.error),
              ),
            if (visible.stage == DepthStage.complete &&
                visible.outputNodeId == null)
              Text(context.t(LocaleKeys.productionDepthLibraryOnly)),
            if (active) ...[
              const SizedBox(height: RevericSpacing.lg),
              LinearProgressIndicator(value: visible.progress),
              if (visible.progress != null)
                Text(
                  '${(visible.progress! * 100).round()}%',
                  style: typo.uiSmall,
                ),
              const SizedBox(height: RevericSpacing.lg),
              Text(
                context.t(LocaleKeys.productionDepthBackground),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ],
          ] else if (!requested)
            Text(context.t(LocaleKeys.productionDepthNoTask))
          else if (ready.data != true)
            Text(
              context.t(
                LocaleKeys.productionDepthPrepare,
                namedArgs: {
                  'size': (controller.models.manifest.bytes / 1000000)
                      .toStringAsFixed(1),
                },
              ),
            ),
        ],
      ),
      actions: [
        RevericButton.text(
          label: context.t(LocaleKeys.commonClose),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (active)
          RevericButton.secondary(
            label: context.t(LocaleKeys.commonCancel),
            onPressed: task!.stage == DepthStage.saving
                ? null
                : () => command(controller.cancel),
          )
        else if (targetNovel != null &&
            targetNode != null &&
            visible?.stage != DepthStage.complete)
          RevericButton.primary(
            label: context.t(
              visible == null
                  ? LocaleKeys.productionDepthStart
                  : LocaleKeys.commonRetry,
            ),
            onPressed:
                ready.connectionState != ConnectionState.done || ready.hasError
                ? null
                : () =>
                      command(() => controller.start(targetNovel, targetNode)),
          ),
      ],
    );
  }
}
