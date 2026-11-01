// 职责: 验证 AppSettingsNotifier 以单个聚合 key 读写编辑器设置，并保持排除项独立。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/editor_settings_data.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/testing.md

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' hide AppSettings;
import 'package:reveric/shared/models/editor_settings_data.dart';
import 'package:reveric/shared/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('writes editor changes only to editor_settings', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appSettingsDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final initialSettings = await container.read(appSettingsProvider.future);
    expect(initialSettings.editorFontColorHex, isEmpty);
    expect(container.read(editorFontColorProvider), isNull);
    expect(initialSettings.editorMinimapEnabled, isFalse);
    expect(initialSettings.editorLineNumbersEnabled, isFalse);
    final notifier = container.read(appSettingsProvider.notifier);
    await notifier.setEditorFontSize(22);
    await notifier.setEditorFontColorHex(' a1b2c3 ');
    await notifier.setEditorMinimapEnabled(true);
    await notifier.setEditorLineNumbersEnabled(true);
    await notifier.setEditorEntityRecognitionEnabled(false);
    await notifier.setEditorLineStyle(EditorLineStyle.denseDashed);
    await notifier.setEditorFormatIndentCount(5);

    final aggregateRaw = await database.appSettingsDao.get(
      EditorSettingsData.appSettingsKey,
    );
    final aggregate = EditorSettingsData.decode(
      aggregateRaw!,
      fallback: EditorSettingsData.defaultsForLanguage('zh_CN'),
    );
    expect(aggregate.fontSize, 22);
    expect(aggregate.fontColorHex, '#A1B2C3');
    container.invalidate(appSettingsProvider);
    final reloaded = await container.read(appSettingsProvider.future);
    expect(reloaded.editorFontColorHex, '#A1B2C3');
    expect(container.read(editorFontColorProvider), const Color(0xFFA1B2C3));
    expect(aggregate.minimapEnabled, isTrue);
    expect(aggregate.lineNumbersEnabled, isTrue);
    expect(aggregate.entityRecognitionEnabled, isFalse);
    expect(aggregate.lineStyle, 'denseDashed');
    expect(aggregate.formatIndentCount, 5);
    for (final key in const [
      'editor_font_size',
      'editor_font_family',
      'editor_entity_recognition_enabled',
    ]) {
      expect(await database.appSettingsDao.has(key), isFalse, reason: key);
    }

    final beforeExcludedWrites = aggregateRaw;
    await notifier.setChapterSortDescending(true);
    await container
        .read(novelEditorPaneLayoutProvider.notifier)
        .save(
          const NovelEditorPaneLayout(
            railWidth: 180,
            sidebarWidth: 320,
            aiPanelWidth: 400,
          ),
        );
    expect(
      await database.appSettingsDao.get(EditorSettingsData.appSettingsKey),
      beforeExcludedWrites,
    );
    expect(
      await database.appSettingsDao.get('chapter_sort_descending'),
      'true',
    );
    expect(
      await database.appSettingsDao.has('novel_editor_pane_layout'),
      isTrue,
    );

    await expectLater(
      notifier.setEditorFontColorHex('not-a-color'),
      throwsFormatException,
    );
    expect(container.read(editorFontColorProvider), const Color(0xFFA1B2C3));

    await notifier.setEditorFontColorHex('');
    expect(container.read(editorFontColorProvider), isNull);
    await notifier.setEditorFontColorHex('#123456');
    await notifier.resetEditorTypography();
    final reset = await container.read(appSettingsProvider.future);
    expect(reset.editorFontColorHex, isEmpty);
    expect(reset.editorFontSize, AppSettings.defaultEditorFontSize);
    expect(reset.editorLineNumbersEnabled, isTrue);
    container.invalidate(appSettingsProvider);
    expect(
      (await container.read(appSettingsProvider.future)).editorFontColorHex,
      isEmpty,
    );
    expect(container.read(editorFontColorProvider), isNull);
  });

  test(
    'ignores legacy editor keys when aggregate settings are absent',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      await database.appSettingsDao.set(key: 'editor_font_size', value: '19');
      await database.appSettingsDao.set(
        key: 'editor_entity_recognition_enabled',
        value: 'false',
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsDatabaseProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final settings = await container.read(appSettingsProvider.future);

      expect(
        settings.editorFontSize,
        EditorSettingsData.defaultsForLanguage('zh_CN').fontSize,
      );
      expect(settings.editorFontColorHex, isEmpty);
      expect(settings.editorEntityRecognitionEnabled, isTrue);
    },
  );
}
