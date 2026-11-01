// 职责: 移动端地图分区列表 — 每个世界一张卡片（已出图显示缩略图，未出图显示占位），
//       点击进入地图工作台，左滑删除，新建世界。地点树在工作台的地点抽屉里管理。
// 关联文件:
//   lib/mobile/features/map/studio_page.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/mobile/widgets/delete_confirm.dart
//   lib/shared/models/map_studio_nav.dart
//   lib/shared/models/map_studio_models.dart
//   lib/shared/services/map_image_store.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/file-access.md
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/database/novel_content_database.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/map_studio_models.dart';
import '../../shared/models/map_studio_nav.dart';
import '../../shared/providers/maps_providers.dart';
import '../../shared/services/map_image_store.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/screenplay/labels.dart';
import '../features/map/studio_page.dart';
import 'delete_confirm.dart';
import 'section_scaffold.dart';

class MobileMapsPanel extends ConsumerWidget {
  const MobileMapsPanel({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.onCreate,
  });

  final String novelId;
  final String databasePath;

  /// 新建世界入口由标题栏右上角承载；空状态引导按钮复用同一回调。
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(locationsProvider(databasePath));
    final locations = locationsAsync.asData?.value ?? const <Location>[];
    final maps =
        ref.watch(mapsProvider(databasePath)).asData?.value ??
        const <NovelMap>[];

    if (locationsAsync.isLoading && locations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final worlds = [...mapWorldsOf(locations)]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (worlds.isEmpty) {
      return MobileSectionEmptyState(
        icon: RevericIcons.public,
        sectionLabel: context.t(LocaleKeys.workspaceMaps),
        hint: context.t(LocaleKeys.workspaceMapsHint),
        actionLabel: context.t(LocaleKeys.mapEditorCreateWorldTitle),
        onCreate: onCreate,
        actionKey: const ValueKey('mobile_maps_empty_create_button'),
      );
    }

    final locationById = {
      for (final location in locations) location.id: location,
    };

    Future<void> deleteWorld(Location world) async {
      final service = ref.read(locationsServiceProvider(databasePath));
      final confirmed = await showMobileDeleteConfirm(
        context,
        title: world.name,
        blockedReason: screenplayInUseBlockedReason(
          context,
          introKey: LocaleKeys.screenplayLocationInUse,
          references: service.getScreenplaySceneReferences(world.id),
        ),
      );
      if (!confirmed) {
        return;
      }
      await service.deleteLocation(world.id);
    }

    return ListView(
      padding: mobileSectionListPadding,
      children: [
        for (final world in worlds)
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.md),
            child: _WorldCard(
              world: world,
              settings: MapStudioSettings.fromMap(
                maps
                    .where((map) => map.locationId == world.id)
                    .firstOrNull
                    ?.settings,
              ),
              placeCount: locations
                  .where(
                    (location) => mapLocationAncestors(
                      location.id,
                      locationById,
                    ).any((item) => item.id == world.id),
                  )
                  .length,
              onTap: () => openMobileMapStudioPage(
                context,
                novelId: novelId,
                databasePath: databasePath,
                worldId: world.id,
              ),
              onDelete: () => deleteWorld(world),
            ),
          ),
      ],
    );
  }
}

class _WorldCard extends StatelessWidget {
  const _WorldCard({
    required this.world,
    required this.settings,
    required this.placeCount,
    required this.onTap,
    required this.onDelete,
  });

  final Location world;
  final MapStudioSettings settings;
  final int placeCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final image = settings.hasImage ? settings.image : null;
    return MobileSectionCard(
      cardKey: ValueKey('mobile_maps_world_${world.id}'),
      onTap: onTap,
      onDelete: onDelete,
      deleteLabel: context.t(LocaleKeys.commonDelete),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(RevericRadius.large - 1),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: ColoredBox(
                color: colors.surfaceDim,
                child: image == null
                    ? const _ThumbnailPlaceholder()
                    : _WorldThumbnail(relativePath: image),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(RevericSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        world.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.t(
                          LocaleKeys.mobileEditorSubLocationCount,
                          namedArgs: {'count': '$placeCount'},
                        ),
                        style: typo.uiTiny.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                image == null
                    ? MobileSectionTagChip(
                        label: context.t(LocaleKeys.mapEditorStudioNotDrawn),
                        backgroundColor: colors.accent.withValues(alpha: 0.12),
                        foregroundColor: colors.accent,
                      )
                    : Text(
                        context
                            .t(LocaleKeys.mapEditorStudioVersionLabel)
                            .replaceFirst('{n}', '${settings.version}'),
                        style: typo.uiTiny.copyWith(color: colors.textSubtle),
                      ),
                const SizedBox(width: RevericSpacing.xs),
                const MobileSectionTrailingChevron(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldThumbnail extends HookWidget {
  const _WorldThumbnail({required this.relativePath});

  final String relativePath;

  @override
  Widget build(BuildContext context) {
    final future = useMemoized(
      () => MapImageStore().absolutePathOf(relativePath),
      [relativePath],
    );
    final absolute = useFuture(future).data;
    if (absolute == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(absolute),
        fit: BoxFit.cover,
        // 列表里只要缩略图，按显示宽度解码，别把整张 4K 地图读进内存。
        cacheWidth:
            (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                .round(),
        errorBuilder: (_, _, _) => const _ThumbnailPlaceholder(),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.all(RevericSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.border),
        ),
        child: Center(
          child: RevericIcon(
            RevericIcons.map_outlined,
            size: 30,
            color: colors.textSubtle,
          ),
        ),
      ),
    );
  }
}
