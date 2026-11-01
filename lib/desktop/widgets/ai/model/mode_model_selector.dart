// 关联文件:
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/shared/hooks/use_ai_mode_model_selection.dart
import 'package:flutter/material.dart';

import '../../../../shared/hooks/use_ai_mode_model_selection.dart';
import '../../../../shared/models/ai_provider.dart';
import '../../../../shared/theme/theme.dart';
import 'model_selector.dart';

class AiModeModelSelector extends StatelessWidget {
  const AiModeModelSelector({super.key, required this.models});

  final AiModeModelSelection models;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final resolved = models.displayed;
    final selector = ModelSelector.compact(
      colors: colors,
      typo: typo,
      modelName: resolved?.displayModelName ?? '',
      resolvedId: resolved?.id ?? '',
      availableModels: models.availableModels,
      disabledModelIds: const <String>{},

      selectedEffort: reasoningEffortForOption(resolved, models.selectedEffort),
      onSelect: models.select,
      onSelectWithEffort: models.selectWithEffort,
    );
    return selector;
  }
}
