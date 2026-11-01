// 职责: 导演台左栏各面板共用的展示件 — 分节标题、对象行、「应用到」条、色块与卡片网格。
// 关联文件:
//   lib/shared/widgets/director/sidebar.dart
//   lib/shared/widgets/director/panels/actions.dart
//   lib/shared/widgets/director/panels/moves.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../components/reveric_context_menu.dart';
import '../../../services/director/session.dart';
import '../../../theme/theme.dart';
import '../strings.dart';

Color hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

String seconds(DirectorSession session, int frame) =>
    (frame / session.history.document.fps).toStringAsFixed(1);

/// 对象 / 机位行的右键菜单：软删除；场景只剩一个机位时不可删。
List<RevericMenuEntry> objectMenu(
  BuildContext context,
  DirectorSession session,
  String id,
) {
  final document = session.history.document;
  final lastCamera =
      document.camera(id) != null && document.activeCameras.length == 1;
  final colors = RevericTheme.colorsOf(context);
  return [
    RevericMenuItem(
      label: tr(context, 'delete'),
      icon: RevericIcons.delete_outline,
      labelColor: colors.error,
      iconColor: colors.error,
      enabled: !lastCamera,
      onTap: () => session.attempt(() {
        session.history.remove(id);
        if (session.selected == id) {
          session.select(null);
        }
      }),
    ),
  ];
}

class Swatch extends StatelessWidget {
  const Swatch(
    this.color, {
    super.key,
    this.size = RevericSizes.directorSwatch,
  });
  final String color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: hexColor(color),
      borderRadius: BorderRadius.circular(RevericRadius.small),
    ),
  );
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key, this.top = 0, this.note});
  final String text;
  final double top;

  /// 标题右侧的灰色短注（如整组不可用的原因）。
  final String? note;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: RevericSpacing.sm),
      child: Row(
        children: [
          Text(
            text,
            style: typo.uiTiny.copyWith(
              color: colors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note != null) ...[
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 列表行：色块或图标 + 名称 + 副标题 + 右侧文字或状态图标，选中时用 selected 底色；
/// 给了 [menu] 时右键（触屏长按）在按下处弹出菜单。
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.subtitle,
    this.trailing,
    this.trailingIcon,
    this.menu,
  });
  final String title;
  final String? subtitle, color, icon, trailing, trailingIcon;
  final bool selected;
  final VoidCallback onTap;
  final List<RevericMenuEntry> Function()? menu;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xxs / 2),
      child: Material(
        color: selected ? colors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          onTap: onTap,
          onSecondaryTapUp: menu == null
              ? null
              : (d) => _openMenu(context, d.globalPosition),
          onLongPress: menu == null
              ? null
              : () {
                  final box = context.findRenderObject()! as RenderBox;
                  _openMenu(
                    context,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  );
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.xs,
            ),
            child: Row(
              children: [
                if (color != null)
                  Swatch(color!)
                else if (icon != null)
                  RevericIcon(
                    icon!,
                    size: RevericSizes.buttonIconSize,
                    color: selected ? colors.accent : colors.textMuted,
                  ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSmall.copyWith(
                          color: selected ? colors.accent : colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiTiny.copyWith(color: colors.textMuted),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                if (trailingIcon != null)
                  RevericIcon(
                    trailingIcon!,
                    size: RevericSizes.directorSmallIcon,
                    color: colors.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, Offset position) {
    onTap();
    showRevericContextMenu(
      context: context,
      position: position,
      entries: menu!(),
    );
  }
}

/// 预设套用目标：选中的对象 + 时间轴选区；没有合适对象时显示提示。
class TargetBar extends StatelessWidget {
  const TargetBar({
    super.key,
    required this.session,
    required this.name,
    required this.empty,
    this.color,
    this.icon,
    this.trailing,
  });
  final DirectorSession session;
  final String? name, color, icon;
  final String empty;

  /// 区间之后的套用选项。
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final (start, end) = session.range;
    return Container(
      key: const ValueKey('director-target-bar'),
      height: RevericSizes.fieldHeightSm,
      margin: const EdgeInsets.only(bottom: RevericSpacing.md),
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
      decoration: BoxDecoration(
        color: name == null ? colors.surfaceContainer : colors.selected,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: name == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                empty,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            )
          : LayoutBuilder(
              // 面板很窄时省掉「应用到」前缀，保住对象名和区间；右侧有套用选项时让得更早。
              builder: (context, constraints) => Row(
                children: [
                  if (constraints.maxWidth >=
                      (trailing == null ? 200 : 300)) ...[
                    Text(
                      tr(context, 'apply_to'),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(width: RevericSpacing.xs),
                  ],
                  if (color != null) Swatch(color!),
                  if (icon != null)
                    RevericIcon(
                      icon!,
                      size: RevericSizes.directorSmallIcon,
                      color: colors.accentWarm,
                    ),
                  const SizedBox(width: RevericSpacing.xxs),
                  Expanded(
                    child: Text(
                      name!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSmallSemibold.copyWith(
                        color: colors.accentWarm,
                      ),
                    ),
                  ),
                  Text(
                    '${seconds(session, start)}–${seconds(session, end)}s',
                    style: typo.uiSmall.copyWith(color: colors.accentWarm),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: RevericSpacing.xs),
                    trailing!,
                  ],
                ],
              ),
            ),
    );
  }
}

/// 卡片网格（默认两列）；子项宽度按面板宽度均分。
class TwoColumnGrid extends StatelessWidget {
  const TwoColumnGrid({super.key, required this.children, this.columns = 2});
  final List<Widget> children;
  final int columns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width =
          (constraints.maxWidth - RevericSpacing.xs * (columns - 1)) / columns;
      return Wrap(
        spacing: RevericSpacing.xs,
        runSpacing: RevericSpacing.xs,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// 预设卡片：可带图标、名称、右侧类别标签和下方说明。
class PresetCard extends StatelessWidget {
  const PresetCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tag,
    this.description,
    this.tooltip,
  });
  final String title;
  final String? icon, tag, description, tooltip;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final enabled = onTap != null;
    final fg = !enabled
        ? colors.textSubtle
        : selected
        ? colors.accentWarm
        : colors.textPrimary;
    final card = Material(
      color: selected ? colors.selected : colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colors.accentWarm : colors.borderInput,
        ),
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RevericSizes.directorActionHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      RevericIcon(
                        icon!,
                        size: RevericSizes.buttonIconSize,
                        color: enabled ? colors.textMuted : colors.textSubtle,
                      ),
                      const SizedBox(width: RevericSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (description == null
                                    ? typo.uiSmall
                                    : typo.uiSmallSemibold)
                                .copyWith(color: fg),
                      ),
                    ),
                    if (tag != null)
                      Text(
                        tag!,
                        style: typo.uiTiny.copyWith(color: colors.textMuted),
                      ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: RevericSpacing.xxs / 2),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? card : Tooltip(message: tooltip!, child: card);
  }
}
