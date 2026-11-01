// 职责: 统一移动弹层的路由外壳、可用高度、安全区、键盘避让和标题布局。
// 关联文件:
//   lib/shared/components/reveric_icon_button.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/components/reveric_icon_button.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';

/// 有标题头时使用默认值；无标题的操作菜单打开框架 handle。
/// 关闭策略与返回值仍由业务入口决定。
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: RevericTheme.colorsOf(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.card),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final keyboard = media.viewInsets.bottom;
        // 框架 handle 占据一个最小触控高度，计入总高度上限。
        final handleHeight = showDragHandle ? kMinInteractiveDimension : 0.0;
        final maxHeight = math.max(
          0.0,
          math.min(
            media.size.height * RevericSizes.mobileSheetMaxHeightFactor -
                handleHeight,
            constraints.maxHeight - keyboard,
          ),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SafeArea(
              top: false,
              // 键盘已经遮住 home indicator，不再占用表单的可用高度。
              minimum: EdgeInsets.only(
                bottom: keyboard == 0 ? RevericSpacing.x5l : 0,
              ),
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: Builder(builder: builder),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 内容自己决定如何滚动；表单默认收缩，长列表可通过 expand 占满可用高度。
class MobileSheetScaffold extends StatelessWidget {
  const MobileSheetScaffold({
    super.key,
    required this.header,
    required this.child,
    this.footer,
    this.expand = false,
    this.showHeaderDivider = true,
  });

  final Widget header;
  final Widget child;
  final Widget? footer;
  final bool expand;
  final bool showHeaderDivider;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (showHeaderDivider)
          Divider(
            height: RevericSizes.dividerThickness,
            color: colors.borderSubtle,
          ),
        Flexible(fit: expand ? FlexFit.tight : FlexFit.loose, child: child),
        if (footer != null) ...[
          Divider(
            height: RevericSizes.dividerThickness,
            color: colors.borderSubtle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.sm,
              RevericSpacing.lg,
              0,
            ),
            child: footer!,
          ),
        ],
      ],
    );
  }
}

class MobileSheetHeader extends StatelessWidget {
  const MobileSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.closeButton,
  });

  /// 关闭按钮为必需交互时用此入口；空回调表示暂时禁用关闭按钮。
  MobileSheetHeader.closable({
    super.key,
    required this.title,
    this.subtitle,
    required VoidCallback? onClose,
    this.leading,
    this.actions = const [],
  }) : closeButton = Builder(
         builder: (context) => RevericIconButton(
           icon: RevericIcons.close,
           tooltip: context.t(LocaleKeys.commonCancel),
           onPressed: onClose,
         ),
       );

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? closeButton;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: subtitle == null ? RevericSpacing.sm : RevericSpacing.lg,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: RevericSpacing.md),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
          ?closeButton,
        ],
      ),
    );
  }
}
