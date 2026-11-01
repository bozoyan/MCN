// 职责: 资产库选择弹窗 — 列出已收进资产库的素材，按类型筛选、单选或移出，可就地导入媒体文件。
// 关联文件:
//   lib/desktop/features/production/support.dart
//   lib/desktop/features/production/node_card.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/assets.json
//   assets/translations/zh-CN/assets.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/file-access.md

import 'dart:io';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_filter_chip.dart';
import '../../../shared/components/reveric_more_menu_button.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/ffmpeg_runner.dart'
    show MediaCancellation;
import '../../../shared/theme/theme.dart';
import '../asset/library_menu_item.dart';
import 'node_card.dart' show ProductionAssetThumb;
import 'support.dart' show productionRun;
import 'builtin_voices.dart';

final _log = AppLogger.forModule('Production');

/// 类型标签顺序与文案；只列调用方允许的类型。
const _typeLabels = {
  'image': LocaleKeys.mediaImages,
  'video': LocaleKeys.mediaVideos,
  'audio': LocaleKeys.mediaAudio,
};

const _mediaExtensions = {
  'image': ['png', 'jpg', 'jpeg', 'webp'],
  'video': ['mp4', 'mov'],
  'audio': ['mp3', 'wav', 'm4a'],
};

class ProductionAssetPicker extends HookWidget {
  const ProductionAssetPicker({
    super.key,
    required this.service,
    required this.types,
    this.confirmLabel,
  });
  final ProductionCanvasService service;
  final Set<String> types;

  /// 主按钮文案；默认「确认」。
  final String? confirmLabel;

  static const double _width = 860;
  static const double _gridHeight = 440;
  static const double _cardHeight = 164;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final tab = useState<String?>(null);
    final picked = useState<AssetRow?>(null);
    final importing = useState(false);
    final assets = useStream(
      useMemoized(
        () => service.library.database.assetDao
            .watchAssets(inLibrary: true)
            .map(
              (rows) => rows
                  .where(
                    (a) =>
                        types.contains(a.type) &&
                        (a.novelId == null || a.novelId == service.novelId),
                  )
                  .toList(),
            ),
        [service, types.join('|')],
      ),
    );
    final visible = (assets.data ?? const <AssetRow>[])
        .where((a) => tab.value == null || a.type == tab.value)
        .toList();
    final extensions = [for (final type in types) ...?_mediaExtensions[type]];

    Future<void> import() async {
      importing.value = true;
      try {
        final file = await openFile(
          acceptedTypeGroups: [
            XTypeGroup(
              label: context.t(LocaleKeys.productionAssets),
              extensions: extensions,
            ),
          ],
        );
        if (file == null) {
          return;
        }
        final asset = await service.library.importFile(
          File(file.path),
          name: file.name,
          novelId: service.novelId,
          purpose: AssetPurpose.production_upload,
          cancellation: MediaCancellation(),
        );
        if (context.mounted && types.contains(asset.type)) {
          tab.value = null;
          picked.value = asset;
        }
      } catch (error, stack) {
        _log.error(
          'asset picker import failed',
          error: error,
          stackTrace: stack,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.mediaImportFailed))),
          );
        }
      } finally {
        if (context.mounted) {
          importing.value = false;
        }
      }
    }

    return RevericDialog.panel(
      width: _width,
      title: Text(context.t(LocaleKeys.productionAssets)),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (types.length > 1)
                  Expanded(
                    child: Wrap(
                      spacing: RevericSpacing.xs,
                      runSpacing: RevericSpacing.xs,
                      children: [
                        RevericFilterChip(
                          label: context.t(LocaleKeys.commonFilterAll),
                          selected: tab.value == null,
                          onTap: () => tab.value = null,
                        ),
                        for (final entry in _typeLabels.entries)
                          if (types.contains(entry.key))
                            RevericFilterChip(
                              label: context.t(entry.value),
                              selected: tab.value == entry.key,
                              onTap: () => tab.value = entry.key,
                            ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (types.contains('audio')) ...[
                  RevericButton.secondary(
                    label: context.t(LocaleKeys.productionBuiltinVoices),
                    icon: RevericIcons.music_notes,
                    onPressed: importing.value
                        ? null
                        : () async {
                            importing.value = true;
                            try {
                              final asset = await pickProductionBuiltinVoice(
                                context,
                                service,
                              );
                              if (asset != null && context.mounted) {
                                Navigator.of(context).pop(asset);
                              }
                            } finally {
                              if (context.mounted) {
                                importing.value = false;
                              }
                            }
                          },
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                ],
                if (extensions.isNotEmpty)
                  RevericButton.secondary(
                    label: context.t(LocaleKeys.commonImport),
                    icon: RevericIcons.upload,
                    loading: importing.value,
                    onPressed: importing.value ? null : import,
                  ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            SizedBox(
              height: _gridHeight,
              child: !assets.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? Center(
                      child: Text(
                        context.t(LocaleKeys.mediaEmpty),
                        style: typo.ui.copyWith(color: colors.textMuted),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            mainAxisExtent: _cardHeight,
                            mainAxisSpacing: RevericSpacing.md,
                            crossAxisSpacing: RevericSpacing.md,
                          ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final asset = visible[index];
                        return _Card(
                          key: ValueKey(asset.id),
                          service: service,
                          asset: asset,
                          selected: picked.value?.id == asset.id,
                          onTap: () => picked.value = asset,
                          onConfirm: () => Navigator.pop(context, asset),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.pop(context),
        ),
        RevericButton.primary(
          label: confirmLabel ?? context.t(LocaleKeys.commonConfirm),
          onPressed: picked.value == null
              ? null
              : () => Navigator.pop(context, picked.value),
        ),
      ],
    );
  }
}

/// 一张素材卡：缩略图、名称、类型 · 规格；在已选中的卡上再点一下直接选定。
class _Card extends HookWidget {
  const _Card({
    super.key,
    required this.service,
    required this.asset,
    required this.selected,
    required this.onTap,
    required this.onConfirm,
  });
  final ProductionCanvasService service;
  final AssetRow asset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hovered = useState(false);
    final spec = asset.width != null && asset.height != null
        ? '${asset.width}×${asset.height}'
        : asset.durationMs != null
        ? '${(asset.durationMs! / 1000).toStringAsFixed(1)}s'
        : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: GestureDetector(
        // 不用 onDoubleTap：它会把单击延迟到双击超时之后，选中反馈发钝。
        onTap: selected ? onConfirm : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : hovered.value
                  ? colors.borderInput
                  : colors.borderSubtle,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: colors.accent.withValues(alpha: .3),
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(RevericRadius.medium),
                      child: ProductionAssetThumb(
                        service: service,
                        asset: asset,
                      ),
                    ),
                    if (hovered.value)
                      Positioned(
                        top: RevericSpacing.xxs,
                        right: RevericSpacing.xxs,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(
                              RevericRadius.small,
                            ),
                          ),
                          child: RevericMoreMenuButton(
                            iconSize: 16,
                            entries: () => [
                              assetLibraryMenuItem(
                                context,
                                asset: asset,
                                onToggle: () => productionRun(
                                  context,
                                  () => service.library.database.assetDao
                                      .setInLibrary(asset.id, false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                asset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
              ),
              Text(
                [
                  context.t(_typeLabels[asset.type] ?? LocaleKeys.mediaTitle),
                  ?spec,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
