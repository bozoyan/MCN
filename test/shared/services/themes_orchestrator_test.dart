// 职责: 验证自定义主题的持久化、继承、版本校验、应用和原子软删除。
// 关联文件:
//   lib/shared/services/themes_orchestrator.dart
//   lib/shared/database/app_database.dart
//   lib/shared/theme/palette.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/daos/app_settings_dao.dart';
import 'package:reveric/shared/services/themes_orchestrator.dart';
import 'package:reveric/shared/theme/palette.dart';

void main() {
  late AppDatabase db;
  Future<Map<String, dynamic>> run(
    String action, [
    Map<String, dynamic> options = const {},
  ]) => ThemesOrchestrator().run(db, {...options, 'action': action});
  Future<Map<String, dynamic>> create() => run('create', {
    'name': '森林书房',
    'baseTheme': 'reveric',
    'lightOverrides': {'accent': '#245c42', 'onAccent': '#ffffff'},
    'darkOverrides': {'accent': '#A4CBA6', 'onAccent': '#172118'},
  });
  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test(
    'create persists overrides, read resolves both modes, apply preserves backgrounds',
    () async {
      await db.appSettingsDao.set(
        key: 'appearance_settings',
        value:
            '{"theme":"ivory","themeMode":"system","backgroundImagePath":"paper.png","backgroundFit":"contain"}',
      );
      final created = await create();
      expect(created['ok'], isTrue, reason: '$created');
      expect(created['applied'], isFalse);
      final id = created['id'] as String;
      final row = await ThemesOrchestrator.readCustomTheme(db, id);
      expect(row.lightOverrides['accent'], '#245C42');
      final read = await run('read', {'id': id});
      expect((read['lightColors'] as Map)['accent'], '#245C42');
      expect((read['darkColors'] as Map)['accent'], '#A4CBA6');
      expect(
        (read['lightColors'] as Map)['canvas'],
        themeColorValues(builtinThemePalettes['reveric']!.$1.colors)['canvas'],
      );
      expect((await run('apply', {'id': id}))['ok'], isTrue);
      final appearance = await ThemesOrchestrator.readAppearance(db);
      expect(appearance.customThemeId, id);
      expect(appearance.themeMode, 'system');
      expect(appearance.backgroundImagePath, 'paper.png');
      expect(appearance.backgroundFit, 'contain');
    },
  );

  test(
    'partial updates clear individual overrides and reject stale revisions',
    () async {
      final created = await create();
      final id = created['id'];
      final updated = await run('update', {
        'id': id,
        'revision': 1,
        'name': '新名字',
        'lightOverrides': {'accent': null, 'onAccent': null},
      });
      expect(updated['ok'], isTrue, reason: '$updated');
      expect(updated['revision'], 2);
      expect(updated['lightOverrides'], isEmpty);
      expect(updated['darkOverrides'], created['darkOverrides']);
      final stale = await run('update', {
        'id': id,
        'revision': 1,
        'name': '旧写入',
      });
      expect(stale['ok'], isFalse);
      expect((await run('read', {'id': id}))['name'], '新名字');
      expect((await run('delete', {'id': id, 'revision': 1}))['ok'], isFalse);
    },
  );

  test(
    'custom inheritance, malformed colors, protected tokens and low contrast are rejected',
    () async {
      final created = await create();
      for (final options in <Map<String, dynamic>>[
        {'baseTheme': created['id']},
        {
          'lightOverrides': {'accent': '#FFFFFF00'},
        },
        {
          'lightOverrides': {'canvas': '#FFFFFF', 'textPrimary': '#FFFFFF'},
        },
        {
          'lightOverrides': {'error': '#123456'},
        },
        {
          'lightOverrides': {'bogus': null},
        },
        {'lightOverrides': 'red'},
        {'unexpected': true},
      ]) {
        final result = await run('create', {
          'name': 'invalid',
          'baseTheme': 'reveric',
          ...options,
        });
        expect(result['ok'], isFalse, reason: '$options');
      }
      expect(await db.select(db.customThemes).get(), hasLength(1));
      expect(
        (await run('update', {
          'id': 'builtin:reveric',
          'revision': 1,
          'name': 'x',
        }))['ok'],
        isFalse,
      );
      expect(
        (await run('delete', {'id': 'builtin:reveric', 'revision': 1}))['ok'],
        isFalse,
      );
      expect(
        (await run('apply', {
          'id': created['id'],
          'themeMode': 'invalid',
        }))['ok'],
        isFalse,
      );
    },
  );

  test(
    'deleting active theme restores its base and keeps its recoverable row',
    () async {
      final created = await create();
      final id = created['id'] as String;
      await run('apply', {'id': id, 'themeMode': 'dark'});
      expect((await run('delete', {'id': id, 'revision': 1}))['ok'], isTrue);
      final appearance = await ThemesOrchestrator.readAppearance(db);
      expect(appearance.customThemeId, isNull);
      expect(appearance.theme, 'reveric');
      expect(appearance.themeMode, 'dark');
      final row = await (db.select(
        db.customThemes,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.deletedAt, isNot(notDeletedSentinel));
      expect(row.lightOverrides, isNotEmpty);
      expect((await run('apply', {'id': id}))['ok'], isFalse);
      expect((await run('read', {'id': id}))['ok'], isFalse);
    },
  );

  test(
    'failed selection write rolls back soft deletion and reports failure',
    () async {
      await db.close();
      final failing = _FailingSettingsDatabase();
      db = failing;
      final created = await create();
      final id = created['id'] as String;
      await run('apply', {'id': id});
      failing.settings.failWrites = true;
      final result = await run('delete', {'id': id, 'revision': 1});
      expect(result['ok'], isFalse);
      expect(result['error_code'], 'theme_operation_failed');
      expect(result['error'].toString(), isNot(contains('injected')));
      expect((await ThemesOrchestrator.readCustomTheme(db, id)).revision, 1);
      expect((await ThemesOrchestrator.readAppearance(db)).customThemeId, id);
    },
  );

  test('built-in lookup remains identical for every brightness', () {
    for (final entry in builtinThemePalettes.entries) {
      expect(
        resolveThemePalette(baseTheme: entry.key, brightness: Brightness.light),
        same(entry.value.$1),
      );
      expect(
        resolveThemePalette(baseTheme: entry.key, brightness: Brightness.dark),
        same(entry.value.$2),
      );
    }
  });
}

class _FailingSettingsDatabase extends AppDatabase {
  _FailingSettingsDatabase() : super.forTest(NativeDatabase.memory());
  late final settings = _FailingSettingsDao(this);
  @override
  AppSettingsDao get appSettingsDao => settings;
}

class _FailingSettingsDao extends AppSettingsDao {
  _FailingSettingsDao(super.db);
  bool failWrites = false;
  @override
  Future<void> set({required String key, required String value}) async {
    if (failWrites) {
      throw StateError('injected appearance write failure');
    }
    await super.set(key: key, value: value);
  }
}
