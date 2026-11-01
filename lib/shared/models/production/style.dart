// 职责: 表达节点风格继承、禁用、预设与自定义风格选择，并提供只读的内置风格目录。
// 关联文件:
//   lib/shared/models/production/style_presets.dart
//   lib/shared/database/daos/production_style_dao.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/desktop/features/production/style_picker.dart
import 'style_presets.dart';

/// 风格引用里指向内置预设的前缀，后接预设 slug。
const productionStylePresetPrefix = 'preset:';

bool isProductionStylePresetRef(String value) =>
    value.startsWith(productionStylePresetPrefix);

sealed class ProductionStyleChoice {
  const ProductionStyleChoice();

  /// 持久化值：null 继承所属剧本的风格，'none' 禁用风格，`preset:<slug>` 指定内置预设，
  /// 其他值指定自定义风格（production_styles）ID。'none' 是保留值；继承在使用时解析，因此会随整个剧本风格变化。
  String? get stored;
  factory ProductionStyleChoice.fromStored(String? value) => switch (value) {
    null => const InheritedProductionStyle(),
    'none' => const NoProductionStyle(),
    final String ref when isProductionStylePresetRef(ref) =>
      PresetProductionStyle(ref.substring(productionStylePresetPrefix.length)),
    final String id => CustomProductionStyle(id),
  };

  /// 剧本的风格列只存「无风格 / 预设 / 自定义风格」，null 表示无风格。
  factory ProductionStyleChoice.fromScreenplay(String? value) => value == null
      ? const NoProductionStyle()
      : ProductionStyleChoice.fromStored(value);
}

final class InheritedProductionStyle extends ProductionStyleChoice {
  const InheritedProductionStyle();
  @override
  String? get stored => null;
}

final class NoProductionStyle extends ProductionStyleChoice {
  const NoProductionStyle();
  @override
  String get stored => 'none';
}

final class PresetProductionStyle extends ProductionStyleChoice {
  PresetProductionStyle(this.presetId) {
    if (presetId.trim().isEmpty) {
      throw const FormatException('Style preset ID required');
    }
  }
  final String presetId;
  @override
  String get stored => '$productionStylePresetPrefix$presetId';
}

final class CustomProductionStyle extends ProductionStyleChoice {
  CustomProductionStyle(this.styleId) {
    if (styleId.trim().isEmpty ||
        styleId == 'none' ||
        isProductionStylePresetRef(styleId)) {
      throw const FormatException('Custom style ID required');
    }
  }
  final String styleId;
  @override
  String get stored => styleId;
}

/// 风格分类：预设分真人 / 2D / 3D，用户自建的风格固定为 custom。
enum ProductionStyleCategory { live_action, two_d, three_d, custom }

/// 套在生成提示词前后的风格文本。
final class ProductionStylePrompt {
  ProductionStylePrompt({
    required this.before,
    required this.after,
    this.category = ProductionStyleCategory.custom,
  }) {
    if ((before.trim().isEmpty && after.trim().isEmpty) ||
        before.length + after.length > 50000) {
      throw const FormatException('Style prompt is required');
    }
  }
  final String before;
  final String after;
  final ProductionStyleCategory category;
  String assemble(String body) =>
      [before, body, after].where((s) => s.isNotEmpty).join('\n');
}

final class ProductionStylePreset {
  ProductionStylePreset._(this.id, this.name, this.prompt);
  final String id;
  final String name;
  final ProductionStylePrompt prompt;
  ProductionStyleCategory get category => prompt.category;
}

final List<ProductionStylePreset> builtinProductionStyles = List.unmodifiable([
  for (final row in productionStylePresetRows)
    ProductionStylePreset._(
      row.id,
      row.name,
      ProductionStylePrompt(
        before: row.before,
        after: row.after,
        category: row.category,
      ),
    ),
]);

final Map<String, ProductionStylePreset> _presetsById = {
  for (final preset in builtinProductionStyles) preset.id: preset,
};

ProductionStylePreset? productionStylePreset(String id) => _presetsById[id];
