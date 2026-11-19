// 职责: 从外置魔搭 LoRA 清单中选择 LoRA，并按分类分组展示触发词预览。
// 关联文件:
//   lib/shared/services/ai/modelscope_catalog.dart
//   lib/shared/widgets/production/image_request_extras_panel.dart
//   lib/shared/components/reveric_dialog.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_dialog.dart';
import '../../components/reveric_search_field.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../services/ai/modelscope_catalog.dart';
import '../../theme/theme.dart';

/// 打开 LoRA 清单选择器；取消或关闭返回 null。
Future<ModelScopeCatalogEntry?> showModelScopeLoraPicker(
  BuildContext context,
) => showRevericDialog<ModelScopeCatalogEntry>(
  context: context,
  builder: (_) => const _ModelScopeLoraPickerDialog(),
);

class _ModelScopeLoraPickerDialog extends HookWidget {
  const _ModelScopeLoraPickerDialog();

  @override
  Widget build(BuildContext context) {
    final catalog = useFuture(
      useMemoized(ModelScopeLoraCatalog.load, const []),
    );
    final query = useState('');
    final search = useTextEditingController();
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);

    final entries = catalog.data?.entries ?? const <ModelScopeCatalogEntry>[];
    final keyword = query.value.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? entries
        : entries
              .where(
                (entry) =>
                    entry.name.toLowerCase().contains(keyword) ||
                    entry.modelId.toLowerCase().contains(keyword),
              )
              .toList(growable: false);

    // 保持清单原有分类顺序，只渲染有命中的分类。
    final grouped = <String, List<ModelScopeCatalogEntry>>{};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.category, () => []).add(entry);
    }

    Widget body;
    if (catalog.connectionState == ConnectionState.waiting) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: RevericSpacing.x3l),
        child: Center(
          child: Text(
            context.t(LocaleKeys.productionImageLoraPickLoading),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
      );
    } else if (filtered.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: RevericSpacing.x3l),
        child: Center(
          child: Text(
            context.t(LocaleKeys.productionImageLoraPickEmpty),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
      );
    } else {
      body = ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final section in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: RevericSpacing.sm,
                bottom: RevericSpacing.xs,
              ),
              child: Text(
                '${section.key} · ${section.value.length}',
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ),
            for (final entry in section.value)
              _CatalogEntryTile(
                entry: entry,
                onTap: () => Navigator.of(context).pop(entry),
              ),
          ],
        ],
      );
    }

    return RevericDialog.panel(
      title: Text(
        context.t(LocaleKeys.productionImageLoraPickTitle),
        style: typo.uiSemibold.copyWith(
          fontSize: typo.body.fontSize,
          color: colors.textPrimary,
        ),
      ),
      width: 560,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericSearchField(
            controller: search,
            hint: context.t(LocaleKeys.productionImageLoraPickSearch),
            onChanged: (value) => query.value = value,
          ),
          const SizedBox(height: RevericSpacing.lg),
          SizedBox(height: 420, child: body),
        ],
      ),
    );
  }
}

class _CatalogEntryTile extends StatelessWidget {
  const _CatalogEntryTile({required this.entry, required this.onTap});

  final ModelScopeCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xs,
          vertical: RevericSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name.isEmpty ? entry.modelId : entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (entry.baseModel.isNotEmpty)
                  Text(
                    entry.baseModel,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              entry.modelId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiTiny.copyWith(color: colors.textSecondary),
            ),
            if (entry.triggerWord.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '${context.t(LocaleKeys.productionImageLoraTrigger)}${entry.triggerWord}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typo.uiTiny.copyWith(color: colors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
