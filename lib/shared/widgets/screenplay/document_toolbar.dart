// 职责: 按双端原有紧凑工具条样式呈现整集文档的元素命令与宿主操作。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/shared/widgets/screenplay/document_rows.dart
//   lib/shared/widgets/screenplay/element_options.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../components/horizontal_wheel_scroll.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'document_rows.dart';
import 'element_options.dart';

class ScreenplayDocumentToolbar extends HookWidget {
  const ScreenplayDocumentToolbar({
    super.key,
    this.actions,
    this.mobile = false,
    this.trailing,
  });
  final ScreenplayDocumentActions? actions;
  final bool mobile;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final actions = this.actions;
    final mobile = actions?.mobile ?? this.mobile;
    final controller = actions?.session.controller;
    final activeType = useListenableSelector(controller?.document, () {
      if (controller == null ||
          controller.value.isEmpty ||
          !controller.selection.isValid) {
        return null;
      }
      return controller
          .value[controller.positionAt(controller.selection.extentOffset).index]
          .type;
    });
    final buttons = [
      for (var index = 0; index < screenplayElementOptions.length; index++)
        if (mobile)
          SizedBox(
            width: RevericSpacing.x6l,
            child: Tooltip(
              message: context.t(screenplayElementOptions[index].labelKey),
              child: InkWell(
                onTap: actions == null
                    ? null
                    : () => actions.pick(
                        context,
                        screenplayElementOptions[index].type,
                      ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RevericIcon(
                        screenplayElementOptions[index].icon,
                        size: 18,
                        color:
                            screenplayElementOptions[index].type ==
                                    activeType &&
                                activeType != null
                            ? colors.accent
                            : colors.textMuted,
                      ),
                      const SizedBox(height: RevericSpacing.xs),
                      Text(
                        context.t(screenplayElementOptions[index].labelKey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiTiny.copyWith(
                          color:
                              screenplayElementOptions[index].type ==
                                      activeType &&
                                  activeType != null
                              ? colors.accent
                              : colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          Flexible(
            child: _ElementButton(
              option: screenplayElementOptions[index],
              shortcut: index + 1,
              active:
                  screenplayElementOptions[index].type == activeType &&
                  activeType != null,
              enabled: actions != null,
              onTap: () =>
                  actions?.pick(context, screenplayElementOptions[index].type),
            ),
          ),
    ];
    return Container(
      padding: mobile
          ? const EdgeInsets.all(RevericSpacing.xs)
          : const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x3l,
              vertical: RevericSpacing.xxs,
            ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                if (mobile)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: HorizontalWheelScroll(
                          builder: (context, scroll) => SingleChildScrollView(
                            controller: scroll,
                            scrollDirection: Axis.horizontal,
                            child: Row(children: buttons),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: RevericSizes.screenplayPageMaxWidth,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: RevericSpacing.editorPaddingH,
                              ),
                              child: Row(children: buttons),
                            ),
                          ),
                        ),
                        if (constraints.maxWidth >= 960) const _ElementHint(),
                      ],
                    ),
                  ),
                // 保存失败入口覆盖在工具条上，不改变正常工具条和正文的尺寸。
                if (actions != null)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: ListenableBuilder(
                      listenable: actions.session.queue,
                      builder: (context, _) =>
                          actions.session.queue.lastError == null
                          ? const SizedBox.shrink()
                          : Material(
                              color: colors.surfaceContainer,
                              child: IconButton(
                                tooltip: context.t(
                                  LocaleKeys.screenplaySaveFailed,
                                ),
                                onPressed: () => actions.showSaveError(context),
                                icon: RevericIcon(
                                  RevericIcons.error_outline,
                                  size: 16,
                                  color: colors.error,
                                ),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: RevericSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ElementButton extends HookWidget {
  const _ElementButton({
    required this.option,
    required this.shortcut,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final ScreenplayElementOption option;
  final int shortcut;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hover = useState(false);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hovered = hover.value && enabled;
    final foreground = !enabled
        ? colors.textSubtle.withValues(alpha: 0.4)
        : active
        ? colors.textPrimary
        : hovered
        ? colors.textSecondary
        : colors.textMuted;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => hover.value = true,
      onExit: (_) => hover.value = false,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        // 快捷键收进 tooltip：常驻第三行会把整条工具条撑到正文两行高，
        // 而这一栏是编辑时一直挂在头顶的 chrome。
        child: Tooltip(
          message: screenplayElementShortcutLabel(shortcut),
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: active
                  ? colors.selected
                  : hovered
                  ? colors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(RevericRadius.large),
              border: Border.all(
                color: active ? colors.borderInput : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RevericIcon(option.icon, size: 16, color: foreground),
                const SizedBox(height: 2),
                Text(
                  context.t(option.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiTiny.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ElementHint extends StatelessWidget {
  const _ElementHint();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kbd('Tab'),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.screenplayElementHintTab),
          style: typo.uiTiny.copyWith(color: colors.textSubtle),
        ),
        const SizedBox(width: RevericSpacing.md),
        const _Kbd('Enter'),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.screenplayElementHintEnter),
          style: typo.uiTiny.copyWith(color: colors.textSubtle),
        ),
      ],
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: colors.borderInput),
      ),
      child: Text(
        label,
        style: typo.mono.copyWith(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: colors.textMuted,
        ),
      ),
    );
  }
}
