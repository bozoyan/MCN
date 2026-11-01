// 职责: 验证制作设置提示按作品持久化，且不修改剧本内容。
// 关联文件:
//   lib/shared/services/storyboard/service.dart
//   lib/shared/database/novel_content_database.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';

void main() {
  test(
    'prompt state survives reopen and stays isolated from screenplay data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'production-state-',
      );
      final file = File('${directory.path}/content.sqlite');
      var db = NovelContentDatabase.forTest(NativeDatabase(file));
      final other = NovelContentDatabase.forTest(NativeDatabase.memory());
      try {
        await ScreenplayService(db).createInitialStructure();
        final service = StoryboardService(db);
        final original = await service.requireSettings();
        expect(await service.hasSettingsPrompted(), isFalse);

        await service.markSettingsPrompted();
        await service.markSettingsPrompted();
        expect(await service.requireSettings(), original);
        final states = await db.select(db.novelStates).get();
        expect(states, hasLength(1));
        expect(states.single.key, 'production_settings');
        expect(states.single.status, 'prompted');
        expect(await StoryboardService(other).hasSettingsPrompted(), isFalse);

        await db.close();
        db = NovelContentDatabase.forTest(NativeDatabase(file));
        final restored = StoryboardService(db);
        expect(await restored.hasSettingsPrompted(), isTrue);
        expect(await restored.requireSettings(), original);
        final columns = await db
            .customSelect('PRAGMA table_info(screenplays)')
            .get();
        expect(
          columns.map((row) => row.read<String>('name')),
          isNot(contains('production_settings_prompted')),
        );
      } finally {
        await db.close();
        await other.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
