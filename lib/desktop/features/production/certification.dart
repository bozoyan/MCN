// 职责: 制作画布上的 Seedance 合规校验入口：工具条菜单项、节点标题旁的状态标记与错误文案。
// 关联文件:
//   lib/shared/services/ai/assets/certification.dart
//   lib/shared/database/daos/provider_asset_dao.dart
//   lib/desktop/features/production/node_bar.dart
//   lib/desktop/features/production/node_card.dart
//   lib/desktop/features/production/storage_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import '../../../shared/hooks/use_ai_providers.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/provider_asset.dart';
import '../../../shared/services/ai/assets/certification.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/theme/theme.dart';
import 'storage_dialog.dart';
import 'support.dart';

/// 已启用、填好凭据的素材认证渠道；读取中为 null。
List<AiProvider>? useCertificationProviders(AppDatabase database) =>
    useAiProviders(database).data
        ?.where((p) => p.enabled && providerSupportsAssetCertification(p))
        .toList();

/// 素材在各渠道的认证记录；读取中为 null。
List<ProviderAsset>? useCertifications(AppDatabase database, String? assetId) =>
    useStream(
      useMemoized(
        () => assetId == null
            ? Stream.value(const <ProviderAsset>[])
            : database.providerAssetDao.watchByAssets([assetId]),
        [database, assetId],
      ),
    ).data;

/// 这个节点作为参考连到的视频节点所用的渠道；读取中为 null。
Set<String>? useDownstreamVideoProviders(
  ProductionCanvasService service,
  CanvasNode node,
) => useStream(
  useMemoized(
    () => service.watchContent(node.canvasId).asyncMap((content) async {
      final byId = {for (final row in content.nodes) row.id: row};
      final clipIds = {
        for (final edge in content.edges)
          if (edge.type == canvasEdgeTypeInput && edge.sourceNodeId == node.id)
            if (byId[edge.targetNodeId] case final target?
                when target.type == canvasNodeTypeVideo)
              ?target.clipId,
      };
      if (clipIds.isEmpty) {
        return <String>{};
      }
      final clips = await (service.db.select(
        service.db.productionClips,
      )..where((t) => t.id.isIn(clipIds))).get();
      return {for (final clip in clips) ?clip.providerId};
    }),
    [service, node.id, node.canvasId],
  ),
).data;

String productionCertifyErrorKey(String code) => switch (code) {
  'invalid_format' => LocaleKeys.productionCertifyErrorFormat,
  'invalid_size' => LocaleKeys.productionCertifyErrorSize,
  'invalid_dimensions' => LocaleKeys.productionCertifyErrorDimensions,
  'invalid_ratio' => LocaleKeys.productionCertifyErrorRatio,
  'configuration_required' => LocaleKeys.productionCertifyErrorConfiguration,
  _ => LocaleKeys.productionCertifyErrorRequest,
};

/// 「…」菜单里的校验项：没有可用渠道时禁用。下游视频节点只用到一个可认证渠道时只给这一项；
/// 否则逐个列出，下游用到的排前面。
List<RevericMenuItem> productionCertifyMenuItems(
  BuildContext context, {
  required ProductionCanvasService service,
  required ProviderAssetService certification,
  required AssetRow asset,
  required List<AiProvider> providers,
  required List<ProviderAsset> records,
  required Set<String> downstream,
}) {
  if (providers.isEmpty) {
    return [
      RevericMenuItem(
        icon: RevericIcons.shield_check,
        label: context.t(LocaleKeys.productionCertify),
        description: context.t(LocaleKeys.productionCertifyUnconfigured),
        enabled: false,
      ),
    ];
  }
  final used = providers.where((p) => downstream.contains(p.id)).toList();
  final shown = used.length == 1
      ? used
      : [...used, ...providers.where((p) => !downstream.contains(p.id))];
  return [
    for (final provider in shown)
      () {
        final record = records
            .where((r) => r.providerId == provider.id)
            .firstOrNull;
        return RevericMenuItem(
          icon: RevericIcons.shield_check,
          label: context.t(
            LocaleKeys.productionCertifyWith,
            namedArgs: {'provider': provider.name},
          ),
          description: switch (record?.status) {
            ProviderAssetStatus.processing => context.t(
              LocaleKeys.productionCertifyProcessing,
            ),
            ProviderAssetStatus.active => context.t(
              LocaleKeys.productionCertifyActive,
            ),
            ProviderAssetStatus.failed =>
              '${context.t(LocaleKeys.productionCertifyFailed)} · '
                  '${context.t(productionCertifyErrorKey(record!.errorCode ?? ''))}',
            null => null,
          },
          enabled:
              record?.status != ProviderAssetStatus.processing &&
              record?.status != ProviderAssetStatus.active,
          onTap: () => productionRun(context, () async {
            if (!await ensureReferenceStorage(
              context,
              certification.references,
            )) {
              return;
            }
            final media = await service.requireFile(asset.path!, type: 'image');
            await certification.certify(
              assetId: asset.id,
              providerId: provider.id,
              file: File(service.library.resolvePath(media.path)),
              mimeType: media.mimeType,
              name: asset.name,
            );
          }),
        );
      }(),
  ];
}

/// 节点标题旁的校验状态：任一渠道通过即算通过，其次是校验中，最后是失败。
class ProductionCertificationMark extends HookWidget {
  const ProductionCertificationMark({
    super.key,
    required this.database,
    required this.assetId,
  });
  final AppDatabase database;
  final String? assetId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final statuses = {
      for (final r in useCertifications(database, assetId) ?? const [])
        r.status,
    };
    final color = statuses.contains(ProviderAssetStatus.active)
        ? colors.accent
        : statuses.contains(ProviderAssetStatus.processing)
        ? colors.textMuted
        : statuses.contains(ProviderAssetStatus.failed)
        ? colors.error
        : null;
    if (color == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: RevericSpacing.xxs),
      child: RevericIcon(RevericIcons.shield_check, size: 12, color: color),
    );
  }
}
