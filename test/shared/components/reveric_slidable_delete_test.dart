// 职责: 验证通用左滑删除组件展示删除操作，并将确认后的删除命令回传给调用方。
// 关联文件:
//   lib/shared/components/reveric_slidable_delete.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_slidable_delete.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('reveals the delete action and invokes the delete callback', (
    tester,
  ) async {
    var deleteCount = 0;
    const cardKey = ValueKey('slidable-card');

    await tester.pumpWidget(
      MaterialApp(
        theme: RevericThemeData.reveric.toThemeData(),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(
            body: RevericSlidableDelete(
              borderRadius: BorderRadius.circular(RevericRadius.large),
              deleteLabel: 'Delete',
              onDelete: () {
                deleteCount++;
              },
              childBuilder: (context, borderRadius) => Container(
                key: cardKey,
                height: 72,
                decoration: BoxDecoration(
                  color: RevericTheme.colorsOf(context).surface,
                  borderRadius: borderRadius,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byKey(cardKey), const Offset(-300, 0));
    await tester.pumpAndSettle();

    final card = tester.widget<Container>(find.byKey(cardKey));
    final decoration = card.decoration! as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;
    expect(borderRadius.topRight, Radius.zero);
    expect(borderRadius.bottomRight, Radius.zero);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(deleteCount, 1);
  });
}
