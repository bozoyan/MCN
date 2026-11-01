// 职责: 移动端 Agent 编辑骨架测试 — 验证编辑页头像优先使用内置图片而非 emoji 文本。
// 关联文件:
//   lib/mobile/widgets/agent_edit_scaffold.dart
//   lib/shared/widgets/agent_avatar.dart
// 遵循的 Rules:
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/widgets/agent_edit_scaffold.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/agent_avatar.dart';

void main() {
  testWidgets('AgentEditHero renders builtin avatar asset for agent slug', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RevericThemeData.reveric.toThemeData(),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: const Scaffold(
            body: AgentEditHero(
              icon: RevericIcons.smart_toy_outlined,
              avatarSlug: 'writer',
              emoji: '✍️',
              title: '正文写手',
              subtitle: '编辑智能体',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AgentAvatar), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('✍️'), findsNothing);
  });
}
