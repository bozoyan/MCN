// 职责: 一张地图都没有时的落点 — 选一个顶层地点开始画它的地图。
// 关联文件:
//   lib/desktop/features/map/map_create_dialogs.dart
//   lib/desktop/features/map/map_studio_page.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/services/maps_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/maps_providers.dart';
import '../../../shared/theme/theme.dart';
import 'map_create_dialogs.dart';
import '../../../shared/widgets/map/location_types.dart';

/// 地图不单独新建：这里列出顶层地点，点一个就为它建图并进工作台，
/// 名字和归属都跟着地点走。
class MapsPanel extends HookConsumerWidget {
  const MapsPanel({super.key, required this.databasePath, this.onMapSelected});

  final String databasePath;
  final void Function(String mapId)? onMapSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final locationsAsync = ref.watch(locationsProvider(databasePath));

    return locationsAsync.when(
      data: (locations) {
        final topLevel = [
          for (final location in locations)
            if (location.parentId == null) location,
        ];
        return _buildPicker(context, ref, locations, topLevel);
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (error, stack) => Center(
        child: Text(
          'Error: $error',
          style: typo.body.copyWith(color: colors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildPicker(
    BuildContext context,
    WidgetRef ref,
    List<Location> locations,
    List<Location> topLevel,
  ) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x6l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RevericIcon(
                RevericIcons.map_outlined,
                color: colors.textSubtle,
                size: 32,
              ),
              const SizedBox(height: RevericSpacing.lg),
              Text(
                context.t(LocaleKeys.workspaceNoMaps),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: RevericSpacing.sm),
              Text(
                context.t(
                  topLevel.isEmpty
                      ? LocaleKeys.mapEditorStudioRailNoLocations
                      : LocaleKeys.mapEditorStudioPickPlace,
                ),
                style: typo.ui.copyWith(color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: RevericSpacing.x2l),
              if (topLevel.isEmpty)
                FilledButton.icon(
                  onPressed: () => showCreateLocationDialog(
                    context,
                    databasePath: databasePath,
                    locations: locations,
                  ),
                  icon: const RevericIcon(RevericIcons.add, size: 16),
                  label: Text(context.t(LocaleKeys.mapEditorCreateLocation)),
                )
              else
                for (final location in topLevel)
                  Padding(
                    padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
                    child: OutlinedButton.icon(
                      onPressed: () => _startMapFor(ref, location),
                      icon: const RevericIcon(RevericIcons.add, size: 14),
                      label: Text(
                        context
                            .t(LocaleKeys.mapEditorStudioCreateMapFor)
                            .replaceFirst('{name}', location.name),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startMapFor(WidgetRef ref, Location location) async {
    final service = ref.read(mapsServiceProvider(databasePath));
    final mapId = await service.createMap(
      name: location.name,
      type: suggestMapType(location.type),
      locationId: location.id,
    );
    onMapSelected?.call(mapId);
  }
}
