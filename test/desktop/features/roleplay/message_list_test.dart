// 职责: 验证角色扮演历史首次显示和切换会话时贴底，普通重建不打断用户回看。
// 关联文件:
//   lib/desktop/features/roleplay/message_list.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/models/roleplay_models.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/roleplay/message_list.dart';
import 'package:reveric/shared/models/roleplay_models.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('restored history shows the latest message on first mount', (
    tester,
  ) async {
    // 恢复前没有消息列表；历史加载完成时直接挂载完整列表。
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pumpWidget(_wrap(_list(_session('first'))));
    await tester.pumpAndSettle();

    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent, 1),
      reason: 'Restored history must open at its latest message',
    );
    expect(find.text('first message 19').hitTestable(), findsOneWidget);
  });

  testWidgets('switching equal-length sessions scrolls to the new bottom', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_list(_session('first'))));
    await tester.pumpAndSettle();
    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(position.maxScrollExtent - 48));

    await tester.pumpWidget(_wrap(_list(_session('other'))));
    await tester.pumpAndSettle();

    final restoredPosition = _position(tester);
    expect(
      restoredPosition.pixels,
      closeTo(restoredPosition.maxScrollExtent, 1),
    );
    expect(find.text('other message 19').hitTestable(), findsOneWidget);
  });

  testWidgets('ordinary rebuild preserves the readers scrollback position', (
    tester,
  ) async {
    final session = _session('first');
    await tester.pumpWidget(_wrap(_list(session)));
    await tester.pumpAndSettle();
    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    final scrollbackOffset = position.pixels;
    expect(scrollbackOffset, lessThan(position.maxScrollExtent - 48));

    await tester.pumpWidget(_wrap(_list(session)));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, scrollbackOffset);
  });
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

RoleplaySession _session(String id) {
  final now = DateTime(2026, 10, 2);
  return RoleplaySession(
    id: id,
    novelId: 'novel',
    character: const RoleplayParticipant(
      characterId: 'character',
      name: 'Character',
      role: '',
      biography: '',
    ),
    phase: RoleplayPhase.completed,
    messages: [
      for (var i = 0; i < 20; i++)
        RoleplayMessage(
          id: '${id}_$i',
          speakerId: 'user',
          speakerName: 'user',
          content: '$id message $i',
          timestamp: now,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

Widget _list(RoleplaySession session) => RoleplayMessageList(
  session: session,
  activeRun: null,
  runHistory: const {},
  userName: 'Author',
  userAvatarPath: '',
  onOpenActiveRunDetail: (_) async {},
);

Widget _wrap(Widget child) => MaterialApp(
  theme: RevericThemeData.reveric.toThemeData(),
  home: RevericTheme(
    data: RevericThemeData.reveric,
    child: Scaffold(body: SizedBox(width: 400, height: 320, child: child)),
  ),
);
