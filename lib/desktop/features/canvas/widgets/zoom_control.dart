// 职责: 画布左下工具簇末尾的缩放百分比与向上弹出的缩放菜单，构思画布和制作画布共用。
// 关联文件:
//   lib/desktop/features/canvas/widgets/floating_cluster.dart
//   lib/desktop/features/canvas/widgets/glass.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/production/board.dart
//   lib/shared/components/reveric_popover.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../../../../shared/components/reveric_popover.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/canvas_colors.dart';
import '../../../../shared/theme/theme.dart';
import 'floating_cluster.dart';
import 'glass.dart';

/// 工具簇最右侧的缩放百分比；点开向上弹出缩放菜单（缩小 / 放大 / 适应视图 / 定档）。
class CanvasZoomControl extends StatelessWidget {
  const CanvasZoomControl({
    super.key,
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onZoomTo,
  });

  /// 当前缩放；在 [Observer] 里调用，镜头变化时百分比跟着刷新。
  final double Function() zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final ValueChanged<double> onZoomTo;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    String percent() => '${(zoom() * 100).round()}%';
    return RevericPopover(
      up: true,
      alignEnd: true,
      trigger: (context, open, toggle) => CanvasFloatingButton(
        tooltip: open ? null : context.t(LocaleKeys.canvasZoomOptions),
        divider: true,
        selected: open,
        onTap: toggle,
        child: Observer(
          builder: (context) => Text(
            percent(),
            style: typo.uiSmallSemibold.copyWith(
              color: colors.textPrimary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      panel: (context, close) {
        void run(VoidCallback action) {
          close();
          action();
        }

        return CanvasEnter(
          slideFrom: const Offset(0, .04),
          child: SizedBox(
            width: _zoomMenuWidth,
            child: CanvasGlass(
              raised: true,
              radius: RevericRadius.pill + RevericSpacing.sm,
              padding: const EdgeInsets.all(RevericSpacing.sm),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.lg,
                        ),
                        child: Observer(
                          builder: (context) => Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${(zoom() * 100).round()}',
                                  style: typo.ui.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                              ),
                              Text(
                                '%',
                                style: typo.ui.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _ZoomMenuItem(
                      label: context.t(LocaleKeys.canvasZoomOut),
                      shortcut: _shortcut('-'),
                      onTap: () => run(onZoomOut),
                    ),
                    _ZoomMenuItem(
                      label: context.t(LocaleKeys.canvasZoomIn),
                      shortcut: _shortcut('='),
                      onTap: () => run(onZoomIn),
                    ),
                    _ZoomMenuItem(
                      label: context.t(LocaleKeys.canvasFitToView),
                      onTap: () => run(onFit),
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                    _ZoomMenuItem(
                      label: context.t(
                        LocaleKeys.canvasZoomTo,
                        namedArgs: {'percent': '50%'},
                      ),
                      onTap: () => run(() => onZoomTo(.5)),
                    ),
                    _ZoomMenuItem(
                      label: context.t(
                        LocaleKeys.canvasZoomTo,
                        namedArgs: {'percent': '100%'},
                      ),
                      shortcut: _shortcut('0'),
                      onTap: () => run(() => onZoomTo(1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const double _zoomMenuWidth = 192;

/// 画布获得焦点时 flow 自带的缩放快捷键（⌘/Ctrl + = - 0），菜单只标出真实可用的键。
String _shortcut(String key) {
  final meta =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return meta ? '⌘ $key' : 'Ctrl+$key';
}

class _ZoomMenuItem extends StatelessWidget {
  const _ZoomMenuItem({
    required this.label,
    required this.onTap,
    this.shortcut,
  });

  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final radius = BorderRadius.circular(RevericRadius.pill);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      hoverColor: canvasGlassHover(colors),
      highlightColor: canvasGlassHover(colors),
      splashColor: canvasGlassHover(colors).withValues(alpha: 0),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.only(
            left: RevericSpacing.lg,
            right: RevericSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
              ),
              if (shortcut case final shortcut?)
                Text(
                  shortcut,
                  style: typo.uiSmall.copyWith(color: colors.textSubtle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
