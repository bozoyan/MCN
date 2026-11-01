// 职责: 原子执行主题查询、创建、修改、应用和软删除，统一校验配色与版本。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/app_settings_aggregate_data.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/theme/palette.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/data-deletion.md
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../logger/app_logger.dart';
import '../models/app_settings_aggregate_data.dart';
import '../theme/palette.dart';

final _log = AppLogger.forModule('ThemesOrchestrator');

class ThemesOrchestrator {
  Future<Map<String, dynamic>> run(
    AppDatabase db,
    Map<String, dynamic> command,
  ) async {
    final action = command['action'];
    var recordId = command['id'] ?? 'none';
    final operation = switch (action) {
      'create' => 'INSERT',
      'update' || 'apply' || 'delete' => 'UPDATE',
      _ => 'SELECT',
    };
    try {
      return await db.transaction(() async {
        final appearance = await readAppearance(db);
        final selected = appearance.customThemeId == null
            ? 'builtin:${appearance.theme}'
            : appearance.customThemeId!;
        switch (action) {
          case 'list':
            _options(command, {});
            final rows =
                await (db.select(db.customThemes)
                      ..where((t) => t.deletedAt.equals(notDeletedSentinel))
                      ..orderBy([
                        (t) => OrderingTerm.asc(t.createdAt),
                        (t) => OrderingTerm.asc(t.id),
                      ]))
                    .get();
            return {
              'ok': true,
              'activeId': selected,
              'themeMode': appearance.themeMode,
              'entries': [
                for (final name in builtinThemePalettes.keys)
                  {'id': 'builtin:$name', 'name': name, 'builtin': true},
                for (final row in rows) _json(row),
              ],
            };
          case 'read':
            _options(command, {'id'});
            final id = _text(command, 'id');
            if (id.startsWith('builtin:')) {
              final base = id.substring(8);
              _base(base);
              return {
                'ok': true,
                'id': id,
                'name': base,
                'builtin': true,
                'applied': selected == id,
                ..._palette(base, {}, {}),
              };
            }
            final row = await readCustomTheme(db, id);
            return {
              'ok': true,
              ..._json(row),
              'applied': selected == id,
              ..._palette(row.baseTheme, row.lightOverrides, row.darkOverrides),
            };
          case 'create':
            _options(command, {
              'name',
              'baseTheme',
              'lightOverrides',
              'darkOverrides',
            });
            final name = _name(command);
            final base = _text(command, 'baseTheme');
            final light = _patch({}, command['lightOverrides']);
            final dark = _patch({}, command['darkOverrides']);
            _validate(base, light, dark);
            final id = const Uuid().v4();
            recordId = id;
            await db
                .into(db.customThemes)
                .insert(
                  CustomThemesCompanion.insert(
                    id: id,
                    name: name,
                    baseTheme: base,
                    lightOverrides: light,
                    darkOverrides: dark,
                  ),
                );
            return {
              'ok': true,
              ..._json(await readCustomTheme(db, id)),
              'applied': false,
            };
          case 'update':
            _options(command, {
              'id',
              'revision',
              'name',
              'baseTheme',
              'lightOverrides',
              'darkOverrides',
            });
            final row = await readCustomTheme(db, _text(command, 'id'));
            _revision(command, row);
            if (![
              'name',
              'baseTheme',
              'lightOverrides',
              'darkOverrides',
            ].any(command.containsKey)) {
              throw const FormatException(
                'Provide at least one field to update.',
              );
            }
            final name = command.containsKey('name')
                ? _name(command)
                : row.name;
            final base = command.containsKey('baseTheme')
                ? _text(command, 'baseTheme')
                : row.baseTheme;
            final light = _patch(row.lightOverrides, command['lightOverrides']);
            final dark = _patch(row.darkOverrides, command['darkOverrides']);
            _validate(base, light, dark);
            await (db.update(
              db.customThemes,
            )..where((t) => t.id.equals(row.id))).write(
              CustomThemesCompanion(
                name: Value(name),
                baseTheme: Value(base),
                lightOverrides: Value(light),
                darkOverrides: Value(dark),
                revision: Value(row.revision + 1),
                updatedAt: Value(DateTime.now()),
              ),
            );
            return {
              'ok': true,
              ..._json(await readCustomTheme(db, row.id)),
              'applied': selected == row.id,
            };
          case 'apply':
            _options(command, {'id', 'themeMode'});
            final id = _text(command, 'id');
            final mode = command.containsKey('themeMode')
                ? _text(command, 'themeMode')
                : appearance.themeMode;
            if (!{'light', 'dark', 'system'}.contains(mode)) {
              throw const FormatException(
                'themeMode must be light, dark or system.',
              );
            }
            String base;
            String? customId;
            if (id.startsWith('builtin:')) {
              base = id.substring(8);
              _base(base);
            } else {
              final row = await readCustomTheme(db, id);
              _validate(row.baseTheme, row.lightOverrides, row.darkOverrides);
              base = row.baseTheme;
              customId = row.id;
            }
            await _select(
              db,
              appearance,
              base: base,
              customId: customId,
              mode: mode,
            );
            return {'ok': true, 'id': id, 'applied': true, 'themeMode': mode};
          case 'delete':
            _options(command, {'id', 'revision'});
            final row = await readCustomTheme(db, _text(command, 'id'));
            _revision(command, row);
            await (db.update(
              db.customThemes,
            )..where((t) => t.id.equals(row.id))).write(
              CustomThemesCompanion(
                deletedAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
                revision: Value(row.revision + 1),
              ),
            );
            if (selected == row.id) {
              await _select(
                db,
                appearance,
                base: row.baseTheme,
                customId: null,
                mode: appearance.themeMode,
              );
            }
            return {
              'ok': true,
              'id': row.id,
              'deleted': true,
              'activeId': selected == row.id
                  ? 'builtin:${row.baseTheme}'
                  : selected,
            };
          default:
            throw const FormatException('Unknown themes action.');
        }
      });
    } on FormatException catch (error) {
      return {
        'ok': false,
        'error': error.message,
        'error_code': 'invalid_argument',
      };
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=custom_themes,app_settings operation=$operation action=$action id=$recordId',
        error: error,
        stackTrace: stackTrace,
      );
      return {
        'ok': false,
        'error':
            'Unable to complete the theme operation. No changes were saved.',
        'error_code': 'theme_operation_failed',
      };
    }
  }

  static Future<AppearanceSettingsData> readAppearance(AppDatabase db) async {
    final raw = await db.appSettingsDao.get(
      AppearanceSettingsData.appSettingsKey,
    );
    return raw == null
        ? AppearanceSettingsData.defaults
        : AppearanceSettingsData.decode(raw);
  }

  static Future<CustomTheme> readCustomTheme(AppDatabase db, String id) async {
    final row =
        await (db.select(db.customThemes)..where(
              (t) => t.id.equals(id) & t.deletedAt.equals(notDeletedSentinel),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const FormatException(
        'Custom theme not found. Read themes list for valid IDs; built-in themes cannot be updated or deleted.',
      );
    }
    return row;
  }

  Future<void> _select(
    AppDatabase db,
    AppearanceSettingsData appearance, {
    required String base,
    required String? customId,
    required String mode,
  }) => db.appSettingsDao.set(
    key: AppearanceSettingsData.appSettingsKey,
    value: jsonEncode({
      ...appearance.toJson(),
      'theme': base,
      'customThemeId': customId,
      'themeMode': mode,
    }),
  );

  void _options(Map<String, dynamic> command, Set<String> allowed) {
    final unknown = command.keys.where(
      (key) => key != 'action' && !allowed.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
  }

  String _text(Map<String, dynamic> command, String key) {
    final value = command[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string.');
    }
    return value.trim();
  }

  String _name(Map<String, dynamic> command) {
    final name = _text(command, 'name');
    if (name.length > 100) {
      throw const FormatException('Theme name must be at most 100 characters.');
    }
    return name;
  }

  void _base(String base) {
    if (!builtinThemePalettes.containsKey(base)) {
      throw const FormatException('baseTheme must name a built-in theme.');
    }
  }

  void _revision(Map<String, dynamic> command, CustomTheme row) {
    final revision = command['revision'];
    if (revision != row.revision && revision != row.revision.toString()) {
      throw FormatException(
        'Theme revision conflict. Read ${row.id} again; current revision is ${row.revision}.',
      );
    }
  }

  Map<String, String> _patch(Map<String, String> previous, Object? patch) {
    final next = Map<String, String>.of(previous);
    if (patch == null) {
      return next;
    }
    if (patch is! Map) {
      throw const FormatException('Color overrides must be an object.');
    }
    for (final entry in patch.entries) {
      if (!editableThemeColorNames.contains(entry.key)) {
        throw FormatException('Unknown or protected color: ${entry.key}.');
      }
      if (entry.value == null) {
        next.remove(entry.key);
      } else if (entry.value is String) {
        next[entry.key as String] = (entry.value as String).toUpperCase();
      } else {
        throw FormatException(
          '${entry.key} must be #RRGGBB or null to inherit.',
        );
      }
    }
    return next;
  }

  void _validate(
    String base,
    Map<String, String> light,
    Map<String, String> dark,
  ) {
    _base(base);
    validateThemeContrast(base, Brightness.light, light);
    validateThemeContrast(base, Brightness.dark, dark);
  }

  Map<String, dynamic> _json(CustomTheme row) => {
    'id': row.id,
    'name': row.name,
    'builtin': false,
    'baseTheme': row.baseTheme,
    'lightOverrides': row.lightOverrides,
    'darkOverrides': row.darkOverrides,
    'revision': row.revision,
  };

  Map<String, dynamic> _palette(
    String base,
    Map<String, String> light,
    Map<String, String> dark,
  ) => {
    'lightColors': themeColorValues(
      resolveThemePalette(
        baseTheme: base,
        brightness: Brightness.light,
        overrides: light,
      ).colors,
    ),
    'darkColors': themeColorValues(
      resolveThemePalette(
        baseTheme: base,
        brightness: Brightness.dark,
        overrides: dark,
      ).colors,
    ),
    'editableColors': editableThemeColorNames.toList(),
  };
}
