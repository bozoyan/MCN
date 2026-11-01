// 职责: 独白气泡内容 — 「内心活动」「接下来的行动」两段；流式生成时边收边解析，不露出格式标记。
// 关联文件:
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/services/ai/mode_output_parser.dart
//   lib/desktop/features/monologue/panel.dart
//   lib/mobile/features/monologue/page_widgets.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../services/ai/mode_output_parser.dart';
import '../../theme/theme.dart';
import 'agent_message_card.dart';

class MonologueBody extends StatelessWidget {
  const MonologueBody({
    super.key,
    required this.innerThoughts,
    required this.plannedActions,
    required this.density,
    this.selectable = true,
  });

  /// 生成中的原始输出；两段都还没出现时返回 null，由卡片显示跳动三点。
  static MonologueBody? streaming(String raw, AgentMessageDensity density) {
    final parsed = parseMonologueOutput(raw, partial: true);
    if (parsed.innerThoughts.isEmpty && parsed.plannedActions.isEmpty) {
      return null;
    }
    return MonologueBody(
      innerThoughts: parsed.innerThoughts,
      plannedActions: parsed.plannedActions,
      density: density,
      selectable: false,
    );
  }

  final String innerThoughts;
  final String plannedActions;
  final AgentMessageDensity density;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (innerThoughts.isNotEmpty)
          _Section(
            icon: RevericIcons.psychology_rounded,
            color: colors.accent,
            label: context.t(LocaleKeys.monologueInnerThoughts),
            text: innerThoughts,
            density: density,
            selectable: selectable,
          ),
        if (innerThoughts.isNotEmpty && plannedActions.isNotEmpty)
          const SizedBox(height: RevericSpacing.md),
        if (plannedActions.isNotEmpty)
          _Section(
            icon: RevericIcons.directions_run_rounded,
            color: colors.accentWarm,
            label: context.t(LocaleKeys.monologuePlannedActions),
            text: plannedActions,
            density: density,
            selectable: selectable,
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
    required this.density,
    required this.selectable,
  });

  final String icon;
  final Color color;
  final String label;
  final String text;
  final AgentMessageDensity density;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final body = Text(
      text,
      style: AgentMessageCard.bodyStyle(context, density),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(icon, size: 14, color: color),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              label,
              style: typo.uiSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        selectable ? SelectionArea(child: body) : body,
      ],
    );
  }
}
