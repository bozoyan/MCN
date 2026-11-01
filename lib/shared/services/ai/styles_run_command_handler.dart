// 职责: 通过 Run styles 查询内置和自定义视觉风格，并新建、编辑自定义风格。
// 关联文件:
//   lib/shared/services/ai/tools_run.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/production/style_service.dart
//   lib/shared/models/production/style.dart
//   assets/bundled_skills/screenplay-tools/references/styles.md
import '../../models/production/style.dart';
import '../../models/tool_permission.dart';
import '../production/canvas_service.dart';
import '../production/style_service.dart';

class StylesRunCommandHandler {
  const StylesRunCommandHandler(this.service);
  final ProductionCanvasService service;

  Future<Map<String, dynamic>> run(
    String subcommand,
    Map<String, dynamic> options,
  ) async {
    final allowed = switch (subcommand) {
      'list' => {'search', 'category'},
      'read' => {'style_id'},
      'create' => {'name', 'before', 'after'},
      'update' => {'style_id', 'name', 'before', 'after'},
      _ => throw const FormatException('Unsupported styles action.'),
    };
    if (options.keys.any((key) => !allowed.contains(key)) ||
        options.values.any((value) => value is! String)) {
      throw const FormatException(
        'Invalid styles options. list accepts search/category; read requires style_id; '
        'create requires name and accepts before/after; update requires style_id and accepts name/before/after. '
        'Values must be strings.',
      );
    }
    if (subcommand == 'create' || subcommand == 'update') {
      return _save(subcommand, options);
    }
    final category = options['category'] as String?;
    if (category != null &&
        !ProductionStyleCategory.values.any(
          (value) => value.name == category,
        )) {
      throw const FormatException(
        'Invalid style category. Expected live_action, two_d, three_d or custom.',
      );
    }
    final id = options['style_id'] as String?;
    if (subcommand == 'read' && (id == null || id.trim().isEmpty)) {
      throw const FormatException('styles read requires style_id.');
    }
    final search = (options['search'] as String?)?.trim().toLowerCase();
    final styles = await service.library.database.productionStyleDao
        .watchStyles()
        .first;
    final entries = <Map<String, dynamic>>[
      for (final preset in builtinProductionStyles)
        {
          'id': '$productionStylePresetPrefix${preset.id}',
          'name': preset.name,
          'category': preset.category.name,
          'source': 'builtin',
          if (subcommand == 'read') ...{
            'before': preset.prompt.before,
            'after': preset.prompt.after,
          },
        },
      for (final style in styles)
        {
          'id': style.id,
          'name': style.name,
          'category': ProductionStyleCategory.custom.name,
          'source': 'custom',
          if (subcommand == 'read') ...{
            'before': style.before,
            'after': style.after,
          },
        },
    ];
    if (subcommand == 'read') {
      for (final entry in entries) {
        if (entry['id'] == id) {
          return {'ok': true, ...entry};
        }
      }
      throw const ToolOperationException('not_found', 'Style not found.');
    }
    return {
      'ok': true,
      'type': 'listing',
      'entries': [
        for (final entry in entries)
          if ((category == null || entry['category'] == category) &&
              (search == null ||
                  (entry['name'] as String).toLowerCase().contains(search)))
            entry,
      ],
    };
  }

  Future<Map<String, dynamic>> _save(
    String subcommand,
    Map<String, dynamic> options,
  ) async {
    final database = service.library.database;
    final id = (options['style_id'] as String?)?.trim();
    final current = id == null
        ? null
        : await database.productionStyleDao.getStyle(id);
    if (subcommand == 'update') {
      if (id == null || id.isEmpty) {
        throw const FormatException('styles update requires style_id.');
      }
      if (isProductionStylePresetRef(id)) {
        throw const FormatException(
          'Builtin styles are read-only. Use styles create to save a custom copy.',
        );
      }
      if (current == null) {
        throw const ToolOperationException('not_found', 'Style not found.');
      }
      if (options.length == 1) {
        throw const FormatException(
          'styles update requires at least one of name, before or after.',
        );
      }
    }
    final name = ((options['name'] as String?) ?? current?.name ?? '').trim();
    if (name.isEmpty) {
      throw const FormatException('Style name must not be empty.');
    }
    final saved = await ProductionStyleService(database).save(
      id: current?.id,
      name: name,
      prompt: ProductionStylePrompt(
        before: (options['before'] as String?) ?? current?.before ?? '',
        after: (options['after'] as String?) ?? current?.after ?? '',
      ),
    );
    return {
      'ok': true,
      'id': saved.id,
      'name': saved.name,
      'category': ProductionStyleCategory.custom.name,
      'source': 'custom',
      'before': saved.before,
      'after': saved.after,
    };
  }
}
