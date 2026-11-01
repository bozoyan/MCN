// 职责: App initialization helpers 回归测试 — 验证 onboarding 与 feature usage 记录清理。
// 关联文件:
//   lib/shared/services/app_initialization.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/app_initialization.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('clears onboarding app states and all feature usage rows', () async {
    await markOnboardingCompleted(db);
    await db.appStateDao.set(
      key: appStateKeyChatOnboardingShown,
      value: DateTime.now().toIso8601String(),
    );
    await db.appStateDao.set(key: 'unrelated_state', value: 'keep');
    final now = DateTime.now();
    await db
        .into(db.featureUsages)
        .insert(
          FeatureUsagesCompanion.insert(
            featureId: 'feature_onboarding.cover_studio',
            firstUsedAt: now,
            lastUsedAt: now,
          ),
        );

    await clearOnboardingAndFeatureUsageRecords(db);

    expect(await db.appStateDao.has(appStateKeyOnboardingCompleted), isFalse);
    expect(await db.appStateDao.has(appStateKeyChatOnboardingShown), isFalse);
    expect(await db.appStateDao.get('unrelated_state'), 'keep');
    expect(await db.select(db.featureUsages).get(), isEmpty);
  });
}
