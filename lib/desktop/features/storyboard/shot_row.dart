// 职责: 展示片段标题行（折叠、状态、规格、跳转）及默认展开的提示词。
// 关联文件:
//   lib/desktop/features/storyboard/region.dart
//   lib/shared/models/storyboard/prompt.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/storyboard/prompt.dart';
import '../../../shared/theme/theme.dart';

class ShotRow extends HookWidget {
  const ShotRow({
    super.key,
    required this.shot,
    required this.number,
    this.prompt,
    required this.actions,
    this.marks = const [],
    this.focused = false,
  });
  final ({VoidCallback? onProduce, ValueChanged<Offset> onMenu}) actions;
  final bool focused;
  final ProductionClipRow shot;
  final String number;
  final Widget? prompt;

  /// 跟在标题后面的行内标记：AI 改动圆点、制作状态、最近一次任务。
  final List<Widget> marks;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // 提示词默认完整展开；收起后只剩标题行，不留摘要。
    final expanded = useState(true);
    useEffect(() {
      if (focused) {
        expanded.value = true;
      }
      return null;
    }, [focused]);
    final parts = StoryboardPrompt.parse(shot.prompt).parts;
    final Widget? body = prompt != null
        ? Offstage(offstage: !expanded.value, child: prompt!)
        : expanded.value && parts.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: RevericSpacing.sm),
            child: SelectableText.rich(
              TextSpan(
                style: typo.bodySmall.copyWith(color: colors.textPrimary),
                children: [
                  for (final part in parts)
                    TextSpan(
                      text: part.isReference ? '@${part.label}' : part.text,
                      style: part.isReference
                          ? typo.bodySmall.copyWith(color: colors.accent)
                          : null,
                    ),
                ],
              ),
            ),
          )
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: context.t(LocaleKeys.productionReorder),
                child: Draggable<String>(
                  data: shot.id,
                  feedback: Material(
                    color: colors.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.sm),
                      child: Text('$number ${shot.title}', style: typo.ui),
                    ),
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: RevericIcon(
                      RevericIcons.drag_handle,
                      size: _handleSize,
                      color: colors.textSubtle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.xs),
              // 行内展开/收起是轻量的 disclosure 控件，按 mockup 用 20px 点击区 + 12px 箭头，
              // 不套 32px 的标准图标按钮。
              Tooltip(
                message: context.t(
                  expanded.value
                      ? LocaleKeys.commonCollapse
                      : LocaleKeys.commonExpand,
                ),
                child: Semantics(
                  button: true,
                  expanded: expanded.value,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    onTap: () => expanded.value = !expanded.value,
                    child: SizedBox.square(
                      dimension: _disclosureSize,
                      child: Center(
                        child: RevericIcon(
                          expanded.value
                              ? RevericIcons.caret_down
                              : RevericIcons.caret_right,
                          size: 12,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(number, style: typo.mono.copyWith(color: colors.textSubtle)),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        shot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold,
                      ),
                    ),
                    for (final mark in marks) ...[
                      const SizedBox(width: RevericSpacing.sm),
                      mark,
                    ],
                  ],
                ),
              ),
              Text(
                shot.ratio,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              if (shot.kind == 'video') ...[
                const SizedBox(width: RevericSpacing.lg),
                Text(
                  context.t(
                    LocaleKeys.productionSeconds,
                    namedArgs: {
                      'seconds': shot.durationMs == null
                          ? '—'
                          : '${shot.durationMs! / 1000}'.replaceFirst(
                              RegExp(r'\.0$'),
                              '',
                            ),
                    },
                  ),
                  style: typo.mono.copyWith(color: colors.textMuted),
                ),
              ],
              if (actions.onProduce != null)
                RevericButton.text(
                  label: context.t(LocaleKeys.commonOpen),
                  size: RevericButtonSize.compact,
                  onPressed: actions.onProduce,
                ),
              Builder(
                builder: (buttonContext) => RevericIconButton(
                  icon: RevericIcons.more_horiz,
                  tooltip: context.t(LocaleKeys.commonMoreActions),
                  onPressed: () {
                    final box = buttonContext.findRenderObject()! as RenderBox;
                    actions.onMenu(
                      box.localToGlobal(Offset(0, box.size.height)),
                    );
                  },
                ),
              ),
            ],
          ),
          if (body != null)
            // 正文和编号对齐，并限制行长；编辑器收起时用 Offstage 保活，未保存的输入不丢。
            Padding(
              padding: const EdgeInsets.only(left: _bodyIndent),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: RevericSizes.storyboardPromptMaxWidth,
                  ),
                  child: body,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const double _handleSize = 14;
  static const double _disclosureSize = 20;

  /// 拖动柄 + 折叠箭头之后的位置，即编号所在列。
  static const double _bodyIndent =
      _handleSize + RevericSpacing.xs + _disclosureSize + RevericSpacing.xs;
}
