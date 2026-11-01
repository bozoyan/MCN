// 职责: 小剧场台词气泡内容 — 斜体舞台指示 + 「」台词；流式生成时边收边解析，不露出格式标记。
// 关联文件:
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/services/ai/mode_output_parser.dart
//   lib/desktop/features/theater/line_card.dart
//   lib/mobile/features/theater/page_widgets.dart
import 'package:flutter/material.dart';

import '../../services/ai/mode_output_parser.dart';
import '../../theme/theme.dart';
import 'agent_message_card.dart';

class TheaterLineBody extends StatelessWidget {
  const TheaterLineBody({
    super.key,
    required this.dialogue,
    required this.density,
    this.stageDirection,
    this.selectable = true,
  });

  /// 生成中的原始输出；舞台指示和台词都还没出现时返回 null，由卡片显示跳动三点。
  static TheaterLineBody? streaming(String raw, AgentMessageDensity density) {
    final parsed = parseTheaterOutput(raw, partial: true);
    if (parsed.stageDirection == null && parsed.dialogue.isEmpty) return null;
    return TheaterLineBody(
      dialogue: parsed.dialogue,
      stageDirection: parsed.stageDirection,
      density: density,
      selectable: false,
    );
  }

  final String dialogue;
  final String? stageDirection;
  final AgentMessageDensity density;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final base = AgentMessageCard.bodyStyle(context, density);
    final stage = stageDirection;
    final dialogueText = Text('「$dialogue」', style: base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stage != null && stage.isNotEmpty) ...[
          Text(
            '（$stage）',
            style: base.copyWith(
              color: colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (dialogue.isNotEmpty) const SizedBox(height: RevericSpacing.xs),
        ],
        if (dialogue.isNotEmpty)
          selectable ? SelectionArea(child: dialogueText) : dialogueText,
      ],
    );
  }
}
