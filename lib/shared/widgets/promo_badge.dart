// 职责: 用暖色实底与轻阴影展示推荐、热门等醒目徽章。
// 关联文件:
//   lib/desktop/features/agent_skills/source_card.dart
//   lib/desktop/features/agent_skills/catalog_detail_panel.dart
//   lib/mobile/features/agent_skills/official_tab.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 目录徽章：调用方提供的展示文案（如「推荐」「热门」）。
///
/// 暖色实底、`onAccent` 字色、星标图标、轻阴影。
class RevericPromoBadge extends StatelessWidget {
  const RevericPromoBadge(this.label, {super.key, this.compact = false});

  final String label;

  /// 移动端列表等窄位用更小 padding / 字号。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = label.trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final bg = colors.accentWarm;
    final fg = colors.onAccent;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: compact ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(
            RevericIcons.auto_awesome,
            size: compact ? 11 : 12,
            color: fg,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            text,
            style: (compact ? typo.uiTiny : typo.uiSmall).copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
