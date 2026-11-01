// 职责: 验证制作模型候选随供应商启用、模型修改和删除刷新，且保留输入草稿。
// 关联文件:
//   lib/shared/hooks/use_ai_providers.dart
//   lib/shared/database/daos/ai_provider_dao.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/hooks/use_ai_providers.dart';

class _Editor extends HookWidget {
  const _Editor(this.database);
  final AppDatabase database;
  @override
  Widget build(BuildContext context) {
    final providers = useAiProviders(database);
    final draft = useTextEditingController(text: 'keep my draft');
    return Column(
      children: [
        TextField(controller: draft),
        for (final provider in providers.data ?? <AiProvider>[])
          if (provider.enabled)
            for (final model in provider.audioModels) Text(model),
      ],
    );
  }
}

void main() {
  testWidgets(
    'live provider changes update choices without remounting the editor',
    (tester) async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      var provider = aiProviderBuiltinById('openai')!.copyWith(
        id: 'p',
        type: 'openrouter',
        enabled: false,
        audioModels: ['bytedance-seed/seed-audio-1-0'],
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
      }

      try {
        await db.aiProviderDao.upsert(provider);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Editor(db))));
        await settle();
        expect(find.text('bytedance-seed/seed-audio-1-0'), findsNothing);
        await tester.enterText(find.byType(TextField), 'edited draft');
        provider = provider.copyWith(enabled: true);
        await db.aiProviderDao.upsert(provider);
        await settle();
        expect(find.text('bytedance-seed/seed-audio-1-0'), findsOneWidget);
        provider = provider.copyWith(audioModels: ['minimax/speech-2.8-hd']);
        await db.aiProviderDao.upsert(provider);
        await settle();
        expect(find.text('bytedance-seed/seed-audio-1-0'), findsNothing);
        expect(find.text('minimax/speech-2.8-hd'), findsOneWidget);
        expect(find.text('edited draft'), findsOneWidget);
        await db.aiProviderDao.softDelete(provider.id);
        await settle();
        expect(find.text('minimax/speech-2.8-hd'), findsNothing);
        expect(find.text('edited draft'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
      }
    },
  );
}
