// 职责: 导演台顶栏导出 — 选择截图或视频，弹窗渲染并预览结果，可把结果加入制作画布。
// 关联文件:
//   lib/shared/services/production/staging_export_orchestrator.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/screenplay/staging.dart
//   lib/shared/widgets/screenplay/director_workspace.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:video_player/video_player.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_context_menu.dart';
import '../../components/reveric_dialog.dart';
import '../../components/reveric_icon_button.dart';
import '../../database/app_database.dart';
import '../../services/director/export_task.dart';
import '../../services/production/canvas_service.dart';
import '../../services/production/staging_export_orchestrator.dart';
import '../../services/screenplay/staging.dart';
import '../../theme/theme.dart';
import '../director/strings.dart';

/// 打开导演台的画布节点：导出结果加入画布时挂在它右侧。
typedef ScreenplayDirectorCanvas = ({
  ProductionCanvasService service,
  String nodeId,
});

class DirectorExportButton extends StatelessWidget {
  const DirectorExportButton({
    super.key,
    required this.binding,
    required this.canvas,
    this.compact = false,
  });
  final VideoStagingBinding binding;
  final ScreenplayDirectorCanvas canvas;

  /// 只显示图标。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final session = binding.session;
    void open({required bool still}) => session.attempt(() async {
      // 导出读已保存的修订号，先把待写入的编辑落库。
      await binding.flush();
      if (!context.mounted) {
        return;
      }
      await showRevericDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DirectorExportDialog(
          binding: binding,
          canvas: canvas,
          still: still,
          frame: session.frame.value,
          cameraId: session.cameraMode == 'sequence'
              ? null
              : session.viewCameraId,
        ),
      );
    });

    void showMenu() {
      final box = context.findRenderObject()! as RenderBox;
      unawaited(
        showRevericContextMenu(
          context: context,
          position:
              box.localToGlobal(box.size.bottomRight(Offset.zero)) +
              const Offset(0, RevericSpacing.xs),
          anchor: Alignment.topRight,
          minWidth: 160,
          entries: [
            RevericMenuItem(
              label: tr(context, 'export_still'),
              icon: RevericIcons.image_outlined,
              onTap: () => open(still: true),
            ),
            RevericMenuItem(
              label: tr(context, 'export_video'),
              icon: RevericIcons.movie_outlined,
              onTap: () => open(still: false),
            ),
          ],
        ),
      );
    }

    return compact
        ? RevericIconButton(
            key: const ValueKey('director-export'),
            icon: RevericIcons.download_simple,
            tooltip: tr(context, 'export'),
            onPressed: session.playing ? null : showMenu,
          )
        : RevericButton.primary(
            key: const ValueKey('director-export'),
            icon: RevericIcons.download_simple,
            label: tr(context, 'export'),
            size: RevericButtonSize.compact,
            onPressed: session.playing ? null : showMenu,
          );
  }
}

class _DirectorExportDialog extends HookWidget {
  const _DirectorExportDialog({
    required this.binding,
    required this.canvas,
    required this.still,
    required this.frame,
    required this.cameraId,
  });
  final VideoStagingBinding binding;
  final ScreenplayDirectorCanvas canvas;
  final bool still;

  /// 截图导出的帧和机位；为空机位时按切镜序列取机位。视频按切镜序列导出整段。
  final int frame;
  final String? cameraId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final task = useMemoized(ExportTaskOrchestrator.new);
    useEffect(() => task.dispose, [task]);
    useListenable(task);
    final asset = useState<AssetRow?>(null);
    final failed = useState(false);
    final adding = useState(false);
    final added = useState(false);
    final document = binding.session.history.document;

    Future<void> render() async {
      failed.value = false;
      try {
        asset.value = await StagingExportOrchestrator().render(
          canvas: canvas.service,
          stagingId: binding.stagingId,
          document: document,
          task: task,
          frame: still ? frame : null,
          cameraId: still ? cameraId : null,
          savedRevisionId: '${binding.version}',
        );
        binding.session.exportsRevision.value++;
      } catch (error, stack) {
        if (!context.mounted) {
          return;
        }
        if (task.cancelled) {
          Navigator.pop(context);
          return;
        }
        debugPrint('[Director] export failed: $error\n$stack');
        failed.value = true;
      }
    }

    Future<void> addToCanvas() async {
      adding.value = true;
      try {
        await canvas.service.addStagingOutput(canvas.nodeId, asset.value!.id);
        if (!context.mounted) {
          return;
        }
        added.value = true;
        Navigator.pop(context);
      } catch (error, stack) {
        binding.session.report(error, stack);
      } finally {
        if (context.mounted) {
          adding.value = false;
        }
      }
    }

    useEffect(() {
      unawaited(render());
      return null;
    }, const []);

    final running = asset.value == null && !failed.value;
    final result = asset.value;
    final preview = result == null
        ? Center(
            child: failed.value
                ? Text(
                    tr(context, 'export_failed'),
                    style: typo.uiSmall.copyWith(color: colors.error),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.x4l,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: task.total == 0
                              ? null
                              : task.written / task.total,
                        ),
                        const SizedBox(height: RevericSpacing.sm),
                        Text(
                          trArgs(context, 'export_progress', {
                            'done': '${task.written}',
                            'total': '${task.total}',
                          }),
                          style: typo.uiSmall.copyWith(
                            color: colors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
          )
        : still
        ? Image.file(
            File(canvas.service.library.resolve(result)),
            fit: BoxFit.contain,
          )
        : _VideoPreview(path: canvas.service.library.resolve(result));

    return PopScope(
      canPop: !running,
      child: RevericDialog.panel(
        width: 560,
        title: Text(
          tr(context, still ? 'export_still' : 'export_video'),
          style: typo.uiSemibold.copyWith(fontSize: typo.body.fontSize),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              child: ColoredBox(
                color: colors.surfaceContainer,
                child: AspectRatio(
                  aspectRatio: document.width / document.height,
                  child: preview,
                ),
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (running)
                  RevericButton.secondary(
                    label: tr(context, 'cancel'),
                    onPressed: task.state == OutputState.cancelling
                        ? null
                        : task.cancel,
                  )
                else ...[
                  RevericButton.secondary(
                    label: tr(context, 'close'),
                    onPressed: adding.value
                        ? null
                        : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  if (failed.value)
                    RevericButton.primary(
                      label: tr(context, 'retry'),
                      onPressed: render,
                    )
                  else
                    RevericButton.primary(
                      key: const ValueKey('director-export-add'),
                      icon: added.value ? RevericIcons.check : null,
                      label: tr(
                        context,
                        added.value ? 'added_to_canvas' : 'add_to_canvas',
                      ),
                      loading: adding.value,
                      onPressed: added.value ? null : addToCanvas,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 导出视频的循环预览，点按暂停 / 继续。
class _VideoPreview extends HookWidget {
  const _VideoPreview({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(
      () => VideoPlayerController.file(File(path)),
      [path],
    );
    useEffect(() {
      unawaited(
        controller.initialize().then((_) async {
          await controller.setLooping(true);
          await controller.play();
        }),
      );
      return controller.dispose;
    }, [controller]);
    useListenable(controller);
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () =>
          controller.value.isPlaying ? controller.pause() : controller.play(),
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
