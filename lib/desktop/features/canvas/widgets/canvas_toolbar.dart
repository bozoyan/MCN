// 职责: 画布全宽顶栏 — 返回 / 画布名+面包屑
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_region.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/desktop-window-frame.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../widgets/desktop_window_frame.dart';

/// 画布全宽顶栏 — 返回 / 面包屑,与 novel workspace header 视觉保持一致。
///
/// 结构:`[返回] [小说名 > 画布名]`
///
/// 画布操作按钮(引用/便签/整理布局/清理失效)已下沉到
/// [CanvasBoard] 左下角浮动工具簇,避免占据 chat panel 顶部。
class CanvasToolbar extends HookConsumerWidget {
  const CanvasToolbar({
    super.key,
    this.leadingKey,
    required this.onClose,
    required this.onSave,
    required this.canvasName,
    this.novelName,
    this.locked = false,
  });

  /// 用于标题栏拖拽排除的 key：只应绑定在返回按钮上，避免左侧可拖拽区域被整个占掉。
  final GlobalKey? leadingKey;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final String canvasName;
  final String? novelName;

  /// 免费态只读：标题后挂 Pro 标记，保存按钮隐藏（无内容可改）。
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

    // 返回和面包屑留在顶部；保存按钮单独避让 Windows 窗口按钮。
    final topInset = DesktopWindowFrame.captionSafeTopInset;

    return ColoredBox(
      color: appChromeBackgroundColor(
        colors,
        appBackgroundActive,
        colors.surfaceContainer,
      ),
      child: SizedBox(
        height: DesktopWindowFrame.titleBarHeight + topInset,
        child: Padding(
          padding: EdgeInsets.only(
            left: RevericSpacing.x2l + DesktopWindowFrame.sidebarLeadingInset,
            right: RevericSpacing.x2l,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: DesktopWindowFrame.titleBarHeight,
                  child: Row(
                    children: [
                      _backButton(context, colors),
                      const SizedBox(width: RevericSpacing.sm),
                      Expanded(
                        child: Row(
                          children: [
                            if (novelName != null && novelName!.isNotEmpty) ...[
                              _breadcrumb(context, novelName!, active: false),
                              _breadcrumbSeparator(context, colors),
                            ],
                            Flexible(
                              child: _breadcrumb(
                                context,
                                canvasName.isEmpty
                                    ? context.t(LocaleKeys.canvasTitle)
                                    : canvasName,
                                active: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!locked)
                Padding(
                  padding: EdgeInsets.only(top: topInset),
                  child: SizedBox(
                    height: DesktopWindowFrame.titleBarHeight,
                    child: Center(
                      child: FilledButton.icon(
                        key: const ValueKey('canvas_toolbar_save_button'),
                        onPressed: onSave,
                        icon: const RevericIcon(
                          RevericIcons.save_outlined,
                          size: 16,
                        ),
                        label: Text(context.t(LocaleKeys.commonSave)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context, RevericColors colors) {
    final button = Tooltip(
      message: MaterialLocalizations.of(context).backButtonTooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onClose,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.xs),
          child: RevericIcon(
            RevericIcons.chevron_left,
            size: 18,
            color: colors.accent,
          ),
        ),
      ),
    );
    if (leadingKey != null) {
      return KeyedSubtree(key: leadingKey, child: button);
    }
    return button;
  }

  Widget _breadcrumb(
    BuildContext context,
    String label, {
    required bool active,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      label,
      style: (active ? typo.uiMedium : typo.ui).copyWith(
        color: active ? colors.textPrimary : colors.textMuted,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _breadcrumbSeparator(BuildContext context, RevericColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
      child: Text(
        '>',
        style: RevericTheme.typographyOf(
          context,
        ).ui.copyWith(color: colors.textMuted),
      ),
    );
  }
}
