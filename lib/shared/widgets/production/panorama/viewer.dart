// 职责: 在共享全景纹理上渲染视角，处理旋转、键盘、全屏滚轮与构图辅助。
// 关联文件:
//   lib/shared/widgets/production/panorama/controller.dart
//   lib/shared/widgets/production/panorama/texture.dart
//   lib/shared/widgets/production/panorama/painter.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/performance.md
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../logger/app_logger.dart';
import '../../../theme/theme.dart';
import 'controller.dart';
import 'painter.dart';
import 'texture.dart';

final _log = AppLogger.forModule('Panorama');

class PanoramaViewer extends HookWidget {
  const PanoramaViewer({
    super.key,
    required this.path,
    required this.controller,
    this.interactive = true,
    this.fullscreen = false,
    this.outputWidth = 1920,
  });
  final String path;
  final PanoramaController controller;
  final bool interactive, fullscreen;
  final double outputWidth;
  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final focus = useFocusNode();
    final pending = useMemoized(() async {
      final texture = await PanoramaTextures.acquire(path);
      try {
        return (
          texture: texture,
          shader: (await PanoramaShader.program()).fragmentShader(),
        );
      } catch (_) {
        texture.dispose();
        rethrow;
      }
    }, [path]);
    // 路径切换会释放旧资源，等待新文件时不能继续绘制旧快照。
    final loaded = useFuture(pending, preserveState: false);
    useEffect(() {
      return () {
        pending.then(
          (resource) {
            resource.shader.dispose();
            resource.texture.dispose();
          },
          onError: (Object error, StackTrace stack) => _log.error(
            'texture/shader failed',
            error: error,
            stackTrace: stack,
          ),
        );
      };
    }, [pending]);
    useEffect(() {
      if (interactive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            focus.requestFocus();
          }
        });
      }
      return null;
    }, [interactive, focus]);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    if (loaded.hasError) {
      return Center(
        child: Tooltip(
          message: context.t(LocaleKeys.productionViewPanoramaError),
          child: RevericIcon(
            RevericIcons.broken_image_outlined,
            color: colors.error,
          ),
        ),
      );
    }
    final resource = loaded.data;
    if (resource == null) {
      return ColoredBox(color: colors.surfaceDim);
    }
    final view = controller.view;
    return Focus(
      focusNode: focus,
      canRequestFocus: interactive,
      onKeyEvent: (_, event) {
        if (!interactive || event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        final view = controller.view;
        final next = switch (event.logicalKey) {
          LogicalKeyboardKey.keyW => view.changed(pitch: view.pitch + 5),
          LogicalKeyboardKey.keyS => view.changed(pitch: view.pitch - 5),
          LogicalKeyboardKey.keyA => view.changed(yaw: view.yaw - 5),
          LogicalKeyboardKey.keyD => view.changed(yaw: view.yaw + 5),
          LogicalKeyboardKey.keyQ => view.changed(fov: view.fov - 5),
          LogicalKeyboardKey.keyE => view.changed(fov: view.fov + 5),
          _ => null,
        };
        if (next == null) {
          return KeyEventResult.ignored;
        }
        controller.set(next);
        return KeyEventResult.handled;
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Listener(
          onPointerDown: interactive ? (_) => focus.requestFocus() : null,
          onPointerSignal: fullscreen
              ? (event) {
                  if (event is PointerScrollEvent) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) => controller.set(
                        controller.view.changed(
                          fov: controller.view.fov + event.scrollDelta.dy * .05,
                        ),
                      ),
                    );
                  }
                }
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: interactive ? (_) => controller.begin() : null,
            onPanUpdate: interactive
                ? (details) {
                    final current = controller.view;
                    final scale = current.fov / constraints.maxWidth;
                    controller.update(
                      current.changed(
                        yaw: current.yaw - details.delta.dx * scale,
                        pitch: current.pitch + details.delta.dy * scale,
                      ),
                    );
                  }
                : null,
            onPanEnd: interactive ? (_) => controller.end() : null,
            onPanCancel: interactive ? controller.end : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: PanoramaPainter(
                      resource.shader,
                      resource.texture.image,
                      view,
                    ),
                  ),
                ),
                if (controller.grid)
                  IgnorePointer(
                    child: CustomPaint(painter: _Thirds(colors.onAccent)),
                  ),
                if (fullscreen || controller.error != null)
                  Positioned(
                    right: RevericSpacing.lg,
                    bottom: RevericSpacing.lg,
                    left: RevericSpacing.lg,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          padding: const EdgeInsets.all(RevericSpacing.sm),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(
                              RevericRadius.medium,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (controller.error != null)
                                Text(
                                  context.t(
                                    LocaleKeys.productionViewPanoramaSaveError,
                                  ),
                                  style: typo.uiSmall.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              if (fullscreen)
                                Text(
                                  context.t(
                                    LocaleKeys.productionViewPanoramaHud,
                                    namedArgs: {
                                      'yaw': view.displayYaw.toStringAsFixed(0),
                                      'pitch': view.pitch.toStringAsFixed(0),
                                      'fov': view.fov.toStringAsFixed(0),
                                    },
                                  ),
                                  style: typo.uiSmall,
                                ),
                              if (fullscreen &&
                                  resource.texture.image.width *
                                          view.fov /
                                          360 <
                                      outputWidth / 2)
                                Text(
                                  context.t(
                                    LocaleKeys.productionViewPanoramaQuality,
                                  ),
                                  style: typo.uiTiny.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thirds extends CustomPainter {
  const _Thirds(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .65)
      ..strokeWidth = 1;
    for (final t in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * t, 0),
        Offset(size.width * t, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * t),
        Offset(size.width, size.height * t),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Thirds old) => old.color != color;
}
