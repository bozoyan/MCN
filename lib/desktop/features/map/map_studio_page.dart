// 职责: 地图工作台页面 — 地图列表/地点树、图片画布舞台与制图师面板的三栏装配
// 关联文件:
//   lib/shared/widgets/map/image_map_canvas.dart
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/shared/providers/map_studio_controller.dart
//   lib/shared/services/map_image_store.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/file-access.md
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/map_agent_providers.dart';
import '../../../shared/providers/maps_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/screenplay/labels.dart';
import '../../../shared/services/generate_map_orchestrator.dart';
import '../../../shared/widgets/map/image_map_canvas.dart';
import '../../../shared/widgets/map/start_map_generation.dart';
import 'map_cartographer_panel.dart';
import 'map_create_dialogs.dart';
import '../../../shared/services/map_image_store.dart';
import '../../../shared/providers/map_studio_controller.dart';
import '../../../shared/models/map_studio_models.dart';
import '../../../shared/models/map_studio_nav.dart';

final MapImageStore _imageStore = MapImageStore();
final _log = AppLogger.forModule('MapStudioPage');

class MapStudioPage extends ConsumerWidget {
  const MapStudioPage({
    super.key,
    required this.novelId,
    required this.databasePath,
    this.worldId,
    required this.onWorldSelected,
  });

  final String novelId;
  final String databasePath;
  final String? worldId;

  /// Workspace selection 保存当前地图所属的地点 id：world 本身或它的子地点。
  /// Map 是否已经落库只是该地点的派生状态，不进入导航状态。
  final ValueChanged<String>? onWorldSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapsAsync = ref.watch(mapsProvider(databasePath));
    final locationsAsync = ref.watch(locationsProvider(databasePath));
    if (mapsAsync.isLoading || locationsAsync.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: RevericTheme.colorsOf(context).accent,
        ),
      );
    }
    final maps = mapsAsync.asData?.value;
    final locations = locationsAsync.asData?.value;
    if (maps == null || locations == null) {
      return Center(
        child: Text(
          context.t(LocaleKeys.mapEditorLoadFailed),
          style: RevericTheme.typographyOf(context).ui,
        ),
      );
    }
    final worlds = mapWorldsOf(locations);
    final currentWorld = resolveMapWorld(locations, worldId);

    if (currentWorld == null) {
      return _CreateFirstWorldState(
        databasePath: databasePath,
        locations: locations,
        onWorldCreated: (worldId) => onWorldSelected?.call(worldId),
      );
    }

    return _WorldMapStudio(
      key: ValueKey(currentWorld.id),
      novelId: novelId,
      databasePath: databasePath,
      world: currentWorld,
      worlds: worlds,
      maps: maps,
      locations: locations,
      requestedOwnerId: worldId,
      onWorldSelected: (id) => onWorldSelected?.call(id),
    );
  }
}

/// 工作台在一个 world 内的导航状态：当前看的是哪个地点的地图、选中了哪个地点。
///
/// 选中地点时画布切到「画着它」的那张图 —— 最近一个有图的祖先；进入某个地点
/// 自己的图是单独的动作（地点树的地图图标 / 制图师的打开地图按钮）。
class _MapStudioNav {
  const _MapStudioNav({
    required this.worldId,
    required this.ownerId,
    required this.trail,
    required this.mappedLocationIds,
    required this.parentMap,
    required this.selectedLocationId,
    required this.onLocationSelected,
    required this.onEnterMap,
  });

  final String worldId;

  /// 当前画布这张图所属的地点；可能还没有 Map 记录（待生成）。
  final String ownerId;

  /// 面包屑：从 world 到当前地图所属地点，只含有图的层级。
  final List<Location> trail;

  /// 当前 world 内已经有 Map 记录的地点。
  final Set<String> mappedLocationIds;

  /// 最近一张已经画好的上层地图：子地图的默认画风与可选的画风参考图。
  final NovelMap? parentMap;
  final String? selectedLocationId;
  final ValueChanged<String?> onLocationSelected;
  final ValueChanged<String> onEnterMap;
}

class _WorldMapStudio extends HookConsumerWidget {
  const _WorldMapStudio({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.world,
    required this.worlds,
    required this.maps,
    required this.locations,
    required this.requestedOwnerId,
    required this.onWorldSelected,
  });

  final String novelId;
  final String databasePath;
  final Location world;
  final List<Location> worlds;
  final List<NovelMap> maps;
  final List<Location> locations;

  /// Workspace selection 指定的地图所属地点；外部导航（Agent 投递草稿）靠它进入子地图。
  final String? requestedOwnerId;

  /// 当前地图所属地点变化时回写 workspace selection。
  final ValueChanged<String> onWorldSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerId = useState(requestedOwnerId ?? world.id);
    final selectedLocationId = useState<String?>(null);

    useEffect(() {
      final requested = requestedOwnerId;
      if (requested != null && requested != ownerId.value) {
        ownerId.value = requested;
        selectedLocationId.value = null;
      }
      return null;
    }, [requestedOwnerId]);

    final resolved = MapStudioNav.resolve(
      world: world,
      maps: maps,
      locations: locations,
      requestedOwnerId: ownerId.value,
    );
    final currentOwner = resolved.owner;

    void selectLocation(String? id) {
      selectedLocationId.value = id;
      if (id == null) return;
      ownerId.value = resolved.ownerForSelection(id);
    }

    void enterMap(String id) {
      ownerId.value = id;
      selectedLocationId.value = null;
    }

    // 页面内切图后同步 selection，外部再按同一个 id 导航时不会被当成无变化。
    useEffect(() {
      if (currentOwner.id == requestedOwnerId) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          onWorldSelected(currentOwner.id);
        }
      });
      return null;
    }, [currentOwner.id]);

    final nav = _MapStudioNav(
      worldId: world.id,
      ownerId: currentOwner.id,
      trail: resolved.trail,
      mappedLocationIds: resolved.mappedLocationIds,
      parentMap: resolved.parentMap,
      selectedLocationId: selectedLocationId.value,
      onLocationSelected: selectLocation,
      onEnterMap: enterMap,
    );

    // 点上方的 world 一律回到该 world 自己的图。
    void selectWorld(String id) {
      if (id == world.id) {
        enterMap(world.id);
      } else {
        onWorldSelected(id);
      }
    }

    final currentMap = resolved.currentMap;
    if (currentMap == null) {
      return _PendingMapStudio(
        key: ValueKey(currentOwner.id),
        novelId: novelId,
        databasePath: databasePath,
        world: world,
        owner: currentOwner,
        worlds: worlds,
        locations: locations,
        nav: nav,
        onWorldSelected: selectWorld,
      );
    }

    final mapLocations =
        ref
            .watch(
              mapLocationsProvider(
                databasePath: databasePath,
                mapId: currentMap.id,
              ),
            )
            .asData
            ?.value ??
        const <MapLocation>[];

    return _SelectedMapStudio(
      key: ValueKey(currentOwner.id),
      novelId: novelId,
      databasePath: databasePath,
      map: currentMap,
      worlds: worlds,
      locations: locations,
      mapLocations: mapLocations,
      nav: nav,
      onWorldSelected: selectWorld,
    );
  }
}

class _SelectedMapStudio extends HookConsumerWidget {
  const _SelectedMapStudio({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.map,
    required this.worlds,
    required this.locations,
    required this.mapLocations,
    required this.nav,
    required this.onWorldSelected,
  });

  final String novelId;
  final String databasePath;
  final NovelMap map;
  final List<Location> worlds;
  final List<Location> locations;
  final List<MapLocation> mapLocations;
  final _MapStudioNav nav;
  final ValueChanged<String> onWorldSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final hoverLocationId = useState<String?>(null);
    final toastText = useState<String?>(null);
    final agentDraft = ref.watch(
      mapDesignDraftProvider(
        databasePath: databasePath,
        worldId: map.locationId!,
      ),
    );
    final cartographerOpen = useState(true);

    final settings = MapStudioSettings.fromMap(map.settings);
    final state = ref.watch(mapStudioControllerProvider(databasePath, map.id));

    // Run map draft 可能发生在地图页面之外；草稿抵达时主动露出下一步入口。
    useEffect(() {
      if (agentDraft == null || cartographerOpen.value) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          cartographerOpen.value = true;
        }
      });
      return null;
    }, [agentDraft, map.id]);

    // 一次性提示（错误 / 回读结果）。useEffect 的回调在 build 期间同步执行，
    // 清错误必须推迟到帧末，否则会触发 Riverpod 的 build 期修改检查。
    useEffect(() {
      final message =
          state.errorMessage ??
          (state.phase == MapStudioPhase.viewing ? state.stageNote : null);
      if (message == null || message.isEmpty) {
        return null;
      }
      toastText.value = message;
      if (state.errorMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ref.exists(mapStudioControllerProvider(databasePath, map.id))) {
            ref
                .read(
                  mapStudioControllerProvider(databasePath, map.id).notifier,
                )
                .clearError();
          }
        });
      }
      final timer = Timer(const Duration(seconds: 4), () {
        if (context.mounted) {
          toastText.value = null;
        }
      });
      return timer.cancel;
    }, [state.errorMessage, state.stageNote, state.phase]);

    // 地图字节：优先用待采用草稿，否则按 settings 路径读文件。
    final imageBytes = useState<Uint8List?>(null);
    useEffect(() {
      if (state.draft?.imageBytes != null) {
        imageBytes.value = state.draft!.imageBytes;
        return null;
      }
      var cancelled = false;
      _loadBytes(_imageStore, settings.image).then((bytes) {
        if (!cancelled) imageBytes.value = bytes;
      });
      return () => cancelled = true;
    }, [state.draft, settings.image, settings.version]);

    final locationById = {
      for (final location in locations) location.id: location,
    };

    void selectLocation(String? id) {
      nav.onLocationSelected(id);
      hoverLocationId.value = null;
      if (id != null) {
        cartographerOpen.value = true;
      }
    }

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MapRail(
              databasePath: databasePath,
              worlds: worlds,
              locations: locations,
              mapLocations: mapLocations,
              settings: settings,
              nav: nav,
              onWorldSelected: (id) {
                cartographerOpen.value = true;
                onWorldSelected(id);
              },
              onLocationSelected: selectLocation,
            ),
            Expanded(
              child: _CanvasStage(
                databasePath: databasePath,
                map: map,
                settings: settings,
                state: state,
                imageBytes: imageBytes.value,
                mapLocations: mapLocations,
                locationById: locationById,
                nav: nav,
                hoverLocationId: hoverLocationId.value,
                onSelectionChanged: selectLocation,
                onHoverLocation: (id) => hoverLocationId.value = id,
                cartographerOpen: cartographerOpen.value,
                onOpenCartographer: () => cartographerOpen.value = true,
              ),
            ),
            if (cartographerOpen.value)
              MapCartographerPanel(
                novelId: novelId,
                databasePath: databasePath,
                map: map,
                settings: settings,
                locations: locations,
                selectedLocationId: nav.selectedLocationId,
                mappedLocationIds: nav.mappedLocationIds,
                parentMap: nav.parentMap,
                onSelectionChanged: selectLocation,
                onEnterMap: nav.onEnterMap,
                onClose: () => cartographerOpen.value = false,
              ),
          ],
        ),
        if (toastText.value != null)
          Positioned(
            bottom: RevericSpacing.x3l,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.lg,
                    vertical: RevericSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    toastText.value!,
                    style: RevericTheme.typographyOf(context).uiSmall,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PendingMapStudio extends HookConsumerWidget {
  const _PendingMapStudio({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.world,
    required this.owner,
    required this.worlds,
    required this.locations,
    required this.nav,
    required this.onWorldSelected,
  });

  final String novelId;
  final String databasePath;
  final Location world;

  /// 这张待生成地图所属的地点：world 本身，或作者选择制作地图的子地点。
  final Location owner;
  final List<Location> worlds;
  final List<Location> locations;
  final _MapStudioNav nav;
  final ValueChanged<String> onWorldSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStarting = useState(false);
    final agentDraft = ref.watch(
      mapDesignDraftProvider(databasePath: databasePath, worldId: owner.id),
    );
    // 还没画过的地图默认打开制图师，生成入口收敛在面板里。
    final cartographerOpen = useState(true);

    useEffect(() {
      if (agentDraft == null || cartographerOpen.value) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          cartographerOpen.value = true;
        }
      });
      return null;
    }, [agentDraft, owner.id]);

    /// 面板参数生成：先落库该地点唯一对应的 Map 记录，再按参数出图。
    Future<void> materializeAndGenerate(MapGenerationRequest request) async {
      if (isStarting.value) {
        return;
      }
      isStarting.value = true;
      try {
        await startMapGenerationForLocation(
          ref,
          databasePath: databasePath,
          novelId: novelId,
          owner: owner,
          request: request,
        );
      } catch (error, stackTrace) {
        _log.error(
          '[DB] map materialization failed: table=NovelMaps '
          'operation=INSERT locationId=${owner.id}',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      } finally {
        if (context.mounted) {
          isStarting.value = false;
        }
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MapRail(
          databasePath: databasePath,
          worlds: worlds,
          locations: locations,
          mapLocations: const <MapLocation>[],
          settings: const MapStudioSettings(),
          nav: nav,
          onWorldSelected: (id) {
            cartographerOpen.value = true;
            onWorldSelected(id);
          },
          onLocationSelected: (id) {
            nav.onLocationSelected(id);
            if (id != null) {
              cartographerOpen.value = true;
            }
          },
        ),
        Expanded(
          child: _PendingCanvasStage(
            nav: nav,
            cartographerOpen: cartographerOpen.value,
            onOpenCartographer: () => cartographerOpen.value = true,
          ),
        ),
        if (cartographerOpen.value)
          MapCartographerPanel.pending(
            novelId: novelId,
            databasePath: databasePath,
            pendingWorldId: owner.id,
            locations: locations,
            selectedLocationId: nav.selectedLocationId,
            mappedLocationIds: nav.mappedLocationIds,
            parentMap: nav.parentMap,
            onSelectionChanged: nav.onLocationSelected,
            onEnterMap: nav.onEnterMap,
            onClose: () => cartographerOpen.value = false,
            busy: isStarting.value,
            onGenerateRequest: materializeAndGenerate,
          ),
      ],
    );
  }
}

class _CreateFirstWorldState extends StatelessWidget {
  const _CreateFirstWorldState({
    required this.databasePath,
    required this.locations,
    required this.onWorldCreated,
  });

  final String databasePath;
  final List<Location> locations;
  final ValueChanged<String> onWorldCreated;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        key: const ValueKey('map_studio_create_first_world'),
        onPressed: () async {
          // “创建地图”在没有 world 时实际先创建第一个 world。Map 记录仍等到
          // 用户在工作台点击生成后再创建。
          final worldId = await showCreateWorldDialog(
            context,
            databasePath: databasePath,
            locations: locations,
          );
          if (worldId != null) {
            onWorldCreated(worldId);
          }
        },
        icon: const RevericIcon(RevericIcons.add, size: 16),
        label: Text(context.t(LocaleKeys.workspaceNewMap)),
      ),
    );
  }
}

Future<Uint8List?> _loadBytes(MapImageStore store, String? relativePath) {
  if (relativePath == null || relativePath.isEmpty) {
    return Future<Uint8List?>.value();
  }
  return store.read(relativePath);
}

/// 左栏。上方只列顶层 world；下方列当前 world 的地点树。
/// 子地点的地图不进上方列表，在地点树里以地图图标进入。
class _MapRail extends ConsumerWidget {
  const _MapRail({
    required this.databasePath,
    required this.worlds,
    required this.locations,
    required this.mapLocations,
    required this.settings,
    required this.nav,
    required this.onWorldSelected,
    required this.onLocationSelected,
  });

  final String databasePath;
  final List<Location> worlds;
  final List<Location> locations;
  final List<MapLocation> mapLocations;
  final MapStudioSettings settings;
  final _MapStudioNav nav;
  final ValueChanged<String> onWorldSelected;
  final ValueChanged<String?> onLocationSelected;

  String? get selectedLocationId => nav.selectedLocationId;

  /// 新建地点：上级默认跟随当前选中的地点，建完自动选中。
  Future<void> _createLocation(BuildContext context, {String? parentId}) async {
    final locationId = await showCreateLocationDialog(
      context,
      databasePath: databasePath,
      locations: locations,
      defaultParentId: parentId,
    );
    if (locationId != null) {
      onLocationSelected(locationId);
    }
  }

  /// 新建一个顶层 world。这里只建立世界；它的 Map 记录仍延迟到生成时创建。
  Future<void> _createWorld(BuildContext context) async {
    final worldId = await showCreateWorldDialog(
      context,
      databasePath: databasePath,
      locations: locations,
    );
    if (worldId != null) {
      onWorldSelected(worldId);
    }
  }

  /// 右键地点行：编辑资料 / 删除地点。
  Future<void> _showLocationContextMenu(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
    Location location,
  ) async {
    final colors = RevericTheme.colorsOf(context);
    await showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        RevericMenuItem(
          icon: RevericIcons.edit_outlined,
          iconColor: colors.accent,
          label: context.t(LocaleKeys.commonEdit),
          onTap: () {
            if (context.mounted) {
              _editLocation(context, location);
            }
          },
        ),
        RevericMenuItem(
          icon: RevericIcons.delete_outline,
          iconColor: colors.deletionBorder,
          labelColor: colors.deletionBorder,
          label: context.t(LocaleKeys.commonDelete),
          onTap: () {
            if (context.mounted) {
              _deleteLocation(context, ref, location);
            }
          },
        ),
      ],
    );
  }

  Future<void> _editLocation(BuildContext context, Location location) async {
    await showEditLocationDialog(
      context,
      databasePath: databasePath,
      locations: locations,
      location: location,
    );
  }

  Future<void> _deleteLocation(
    BuildContext context,
    WidgetRef ref,
    Location location,
  ) async {
    final service = ref.read(locationsServiceProvider(databasePath));
    final confirmed = await showConfirmDialog(
      context,
      title: context.t(LocaleKeys.mapEditorDeleteLocationTitle),
      message: context.t(LocaleKeys.mapEditorDeleteLocationConfirm),
      confirmLabel: context.t(LocaleKeys.commonDelete),
      variant: ConfirmDialogVariant.error,
      blockedReason: screenplayInUseBlockedReason(
        context,
        introKey: LocaleKeys.screenplayLocationInUse,
        references: service.getScreenplaySceneReferences(location.id),
      ),
    );
    if (!confirmed) {
      return;
    }
    await service.deleteLocation(location.id);
    // 删除的是当前选中地点时清掉选中态；locationsProvider 是流，列表自动刷新。
    if (selectedLocationId == location.id) {
      onLocationSelected(null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final placedIds = {
      for (final row in mapLocations)
        if (!settings.unmatchedLocationIds.contains(row.locationId))
          row.locationId,
    };

    // 下方这棵树以当前 world 为根。即使 Map 尚未落库，也可以先维护地点。
    final rootId = nav.worldId;
    final childCount = locations
        .where((location) => location.parentId == rootId)
        .length;

    return Container(
      key: const ValueKey('map_studio_world_rail'),
      width: 240,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailSectionHead(
            title: context.t(LocaleKeys.workspaceSidebarMap),
            count: worlds.length,
            onAdd: () => _createWorld(context),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final world in worlds)
                  _MapRailRow(
                    icon: _iconForType(world.type),
                    title: world.name,
                    active: world.id == rootId,
                    onTap: () => onWorldSelected(world.id),
                    onSecondaryTapDown: (details) =>
                        _showLocationContextMenu(context, ref, details, world),
                  ),
              ],
            ),
          ),
          _RailSectionHead(
            title: context.t(LocaleKeys.mapEditorStudioRailPlaces),
            count: childCount,
            dense: true,
            onAdd: () => _createLocation(context, parentId: rootId),
          ),
          Expanded(
            child: childCount > 0
                ? _LocationTree(
                    locations: locations,
                    rootId: rootId,
                    placedIds: placedIds,
                    mappedIds: nav.mappedLocationIds,
                    currentMapOwnerId: nav.ownerId,
                    selectedLocationId: selectedLocationId,
                    onSelected: onLocationSelected,
                    onEnterMap: nav.onEnterMap,
                    onContextMenu: (location, details) =>
                        _showLocationContextMenu(
                          context,
                          ref,
                          details,
                          location,
                        ),
                  )
                : _RailEmptyHint(
                    text: context.t(LocaleKeys.mapEditorStudioRailNoLocations),
                    actionLabel: context.t(LocaleKeys.mapEditorCreateLocation),
                    onTap: () => _createLocation(context, parentId: rootId),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RailSectionHead extends StatelessWidget {
  const _RailSectionHead({
    required this.title,
    required this.onAdd,
    this.count,
    this.dense = false,
  });

  final String title;
  final int? count;
  final bool dense;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.all(RevericSpacing.md),
      child: Row(
        children: [
          Text(
            title,
            style: dense
                ? typo.uiSmallSemibold.copyWith(color: colors.textSecondary)
                : typo.uiSemibold,
          ),
          if (count != null) ...[
            const SizedBox(width: RevericSpacing.xs),
            Text(
              '$count',
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: const RevericIcon(RevericIcons.add, size: 14),
          ),
        ],
      ),
    );
  }
}

class _LocationTree extends StatelessWidget {
  const _LocationTree({
    required this.locations,
    required this.rootId,
    required this.placedIds,
    required this.mappedIds,
    required this.currentMapOwnerId,
    required this.selectedLocationId,
    required this.onSelected,
    required this.onEnterMap,
    this.onContextMenu,
  });

  final List<Location> locations;

  /// 树根 = 当前这张图所属的地点。它自己不出现在树里，只列它的子孙。
  final String rootId;
  final Set<String> placedIds;

  /// 有自己地图的地点：行尾显示地图图标，点它进入那张图。
  final Set<String> mappedIds;
  final String currentMapOwnerId;
  final String? selectedLocationId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String> onEnterMap;
  final void Function(Location location, TapDownDetails details)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final roots = [
      for (final location in locations)
        if (location.parentId == rootId) location,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: RevericSpacing.md),
      children: [for (final root in roots) ..._buildNode(root, 0, context)],
    );
  }

  List<Widget> _buildNode(Location location, int depth, BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isSelected = selectedLocationId == location.id;
    // 展开到 city 一级为止；再往下只有做了地图（或正在做）的地点才展开。
    final hasMap = mappedIds.contains(location.id);
    final isCurrentMap = location.id == currentMapOwnerId;
    final children = _expandsChildren(location.type) || hasMap || isCurrentMap
        ? [
            for (final candidate in locations)
              if (candidate.parentId == location.id) candidate,
          ]
        : const <Location>[];
    return [
      InkWell(
        onTap: () => onSelected(location.id),
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (details) => onContextMenu!(location, details),
        child: Container(
          color: isSelected ? colors.selected.withValues(alpha: 0.4) : null,
          padding: EdgeInsets.only(
            left: RevericSpacing.md + depth * 14,
            right: RevericSpacing.md,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              RevericIcon(_iconForType(location.type), size: 13),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  location.name,
                  style: typo.uiSmall.copyWith(
                    color: isSelected ? colors.accent : colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasMap)
                Tooltip(
                  message: context.t(LocaleKeys.mapEditorStudioOpenMap),
                  child: InkWell(
                    key: ValueKey('map_rail_enter_map_${location.id}'),
                    onTap: () => onEnterMap(location.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.xs,
                      ),
                      child: RevericIcon(
                        RevericIcons.map_outlined,
                        size: 12,
                        color: isCurrentMap ? colors.accent : colors.textMuted,
                      ),
                    ),
                  ),
                ),
              if (placedIds.contains(location.id))
                const RevericIcon(RevericIcons.location_on, size: 11),
            ],
          ),
        ),
      ),
      for (final child in children) ..._buildNode(child, depth + 1, context),
    ];
  }
}

String _iconForType(String type) {
  return switch (type) {
    locationTypeWorld || locationTypeContinent => RevericIcons.public_outlined,
    locationTypeCountry => RevericIcons.rule_outlined,
    locationTypeRegion ||
    locationTypeMountain ||
    locationTypePlain => RevericIcons.landscape,
    locationTypeForest => RevericIcons.eco_outlined,
    locationTypeRiver ||
    locationTypeLake ||
    locationTypeSea ||
    locationTypeIsland => RevericIcons.water,
    locationTypeCity => RevericIcons.location_city,
    locationTypeVillage => RevericIcons.home,
    locationTypeBuilding => RevericIcons.temple_buddhist_outlined,
    _ => RevericIcons.location_on,
  };
}

/// 树展开到 city 一级为止 —— 再往下的街区、建筑、房间画不到地图上。
bool _expandsChildren(String type) => !const {
  locationTypeCity,
  locationTypeDistrict,
  locationTypeVillage,
  locationTypeBuilding,
  locationTypeRoom,
}.contains(type);

/// 上方一行只展示 world 名称；地图是否已生成不在列表中重复标记。
class _MapRailRow extends StatelessWidget {
  const _MapRailRow({
    required this.icon,
    required this.title,
    required this.active,
    required this.onTap,
    this.onSecondaryTapDown,
  });

  final String icon;
  final String title;
  final bool active;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        color: active ? colors.selected.withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.sm,
        ),
        child: Row(
          children: [
            RevericIcon(
              icon,
              size: 14,
              color: active ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: typo.uiSmall.copyWith(
                  color: active ? colors.accent : colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画布顶栏的面包屑：world › … › 当前地图所属地点，前面的层级可点回去。
class _MapTrail extends StatelessWidget {
  const _MapTrail({required this.nav, this.version});

  final _MapStudioNav nav;
  final int? version;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final style = typo.uiSmall.copyWith(color: colors.textMuted);
    final last = nav.trail.last;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final location in nav.trail.take(nav.trail.length - 1)) ...[
          InkWell(
            key: ValueKey('map_trail_${location.id}'),
            borderRadius: BorderRadius.circular(RevericRadius.small),
            onTap: () => nav.onEnterMap(location.id),
            child: Text(
              location.name,
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.xs),
            child: RevericIcon(
              RevericIcons.chevron_right,
              size: 12,
              color: colors.textSubtle,
            ),
          ),
        ],
        Text(
          version == null ? last.name : '${last.name} · v$version',
          style: style,
        ),
      ],
    );
  }
}

class _PendingCanvasStage extends StatelessWidget {
  const _PendingCanvasStage({
    required this.nav,
    required this.cartographerOpen,
    required this.onOpenCartographer,
  });

  final _MapStudioNav nav;
  final bool cartographerOpen;
  final VoidCallback onOpenCartographer;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Column(
      key: const ValueKey('map_studio_pending_canvas'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: Row(
            children: [
              _MapTrail(nav: nav),
              const Spacer(),
              if (!cartographerOpen)
                IconButton(
                  tooltip: context.t(LocaleKeys.mapEditorStudioTitle),
                  onPressed: onOpenCartographer,
                  icon: const RevericIcon(RevericIcons.explore, size: 16),
                ),
              IconButton(
                tooltip: context.t(LocaleKeys.mapEditorStudioExport),
                onPressed: null,
                icon: const RevericIcon(RevericIcons.download, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: colors.surfaceDim,
            alignment: Alignment.center,
            child: _EmptyCard(
              onOpenCartographer: cartographerOpen ? null : onOpenCartographer,
            ),
          ),
        ),
        Container(
          height: RevericSpacing.x3l,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.borderSubtle)),
          ),
        ),
      ],
    );
  }
}

class _CanvasStage extends HookConsumerWidget {
  const _CanvasStage({
    required this.databasePath,
    required this.map,
    required this.settings,
    required this.state,
    required this.imageBytes,
    required this.mapLocations,
    required this.locationById,
    required this.nav,
    required this.hoverLocationId,
    required this.onSelectionChanged,
    required this.onHoverLocation,
    required this.cartographerOpen,
    required this.onOpenCartographer,
  });

  final String databasePath;
  final NovelMap map;
  final MapStudioSettings settings;
  final MapStudioState state;
  final Uint8List? imageBytes;
  final List<MapLocation> mapLocations;
  final Map<String, Location> locationById;
  final _MapStudioNav nav;
  final String? hoverLocationId;
  final ValueChanged<String?> onSelectionChanged;
  final ValueChanged<String?> onHoverLocation;
  final bool cartographerOpen;
  final VoidCallback onOpenCartographer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final stage =
        MapGenerationStage.values[state.stageIndex.clamp(
          0,
          MapGenerationStage.values.length - 1,
        )];
    final hoverLocation = hoverLocationId == null
        ? null
        : locationById[hoverLocationId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: Row(
            children: [
              _MapTrail(nav: nav, version: settings.version),
              const Spacer(),
              if (!cartographerOpen)
                IconButton(
                  tooltip: context.t(LocaleKeys.mapEditorStudioTitle),
                  onPressed: onOpenCartographer,
                  icon: const RevericIcon(RevericIcons.explore, size: 16),
                ),
              IconButton(
                tooltip: context.t(LocaleKeys.mapEditorStudioExport),
                onPressed: settings.hasImage ? () => _export(context) : null,
                icon: const RevericIcon(RevericIcons.download, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: colors.surfaceDim,
            child: imageBytes != null
                ? ImageMapCanvas(
                    map: map,
                    settings: settings,
                    imageBytes: imageBytes,
                    mapLocations: mapLocations,
                    locationById: locationById,
                    selectedLocationId: nav.selectedLocationId,
                    hoveredLocationId: hoverLocationId,
                    onSelectionChanged: onSelectionChanged,
                    onHoverLocation: onHoverLocation,
                  )
                : state.isBusy
                ? const _GeneratingCanvasPlaceholder()
                : Center(
                    child: _EmptyCard(
                      onOpenCartographer: cartographerOpen
                          ? null
                          : onOpenCartographer,
                    ),
                  ),
          ),
        ),
        if (state.isBusy) _GeneratingPanel(stage: stage),
        if (state.phase == MapStudioPhase.review)
          _ReviewBar(
            matchedCount: state.draft?.readResult.matches.length ?? 0,
            candidateCount: state.draft?.places.length ?? 0,
            requiresPlaceRecognition: state.requiresPlaceRecognition,
            onAdopt: () => ref
                .read(
                  mapStudioControllerProvider(databasePath, map.id).notifier,
                )
                .adopt(),
            onRegenerate: () => ref
                .read(
                  mapStudioControllerProvider(databasePath, map.id).notifier,
                )
                .regenerate(),
          ),
        if (!state.isBusy)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.md,
              vertical: RevericSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Text(
              hoverLocation?.name ?? '',
              style: typo.uiTiny.copyWith(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final location = await getSaveLocation(
      suggestedName: '${map.name}-v${settings.version}.png',
    );
    if (location == null) return;
    final absolute = await _imageStore.absolutePathOf(settings.image!);
    if (absolute == null) return;
    await File(absolute).copy(location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.mapEditorStudioExported))),
      );
    }
  }
}

class _GeneratingCanvasPlaceholder extends StatelessWidget {
  const _GeneratingCanvasPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = context.t(LocaleKeys.mapEditorStudioPainting);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x3l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 315),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Semantics(
              liveRegion: true,
              label: label,
              child: DecoratedBox(
                key: const ValueKey('map_studio_generating_canvas'),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(RevericRadius.x2l),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RevericIcon(
                        RevericIcons.map_outlined,
                        size: 24,
                        color: colors.textMuted,
                      ),
                      const SizedBox(height: RevericSpacing.md),
                      Text(
                        label,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratingPanel extends StatelessWidget {
  const _GeneratingPanel({required this.stage});

  final MapGenerationStage stage;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final stageLabels = [
      context.t(LocaleKeys.mapEditorStudioStageRead),
      context.t(LocaleKeys.mapEditorStudioStageImage),
      context.t(LocaleKeys.mapEditorStudioStageLocate),
      context.t(LocaleKeys.mapEditorStudioStageVerify),
    ];
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Text(
              '${stage.index + 1}/${stageLabels.length} ${stageLabels[stage.index]}',
              style: typo.uiSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBar extends StatelessWidget {
  const _ReviewBar({
    required this.matchedCount,
    required this.candidateCount,
    required this.onAdopt,
    required this.onRegenerate,
    required this.requiresPlaceRecognition,
  });

  final int matchedCount;
  final int candidateCount;
  final VoidCallback onAdopt;
  final VoidCallback onRegenerate;
  final bool requiresPlaceRecognition;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.seal_check,
            size: 18,
            color: colors.success,
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.mapEditorStudioReviewTitle),
                  style: typo.uiSmallSemibold,
                ),
                Text(
                  requiresPlaceRecognition
                      ? context.t(
                          LocaleKeys.mapEditorStudioHistoryRecognizeOnApply,
                        )
                      : context
                            .t(LocaleKeys.mapEditorStudioReviewNote)
                            .replaceFirst('{matched}', '$matchedCount')
                            .replaceFirst('{total}', '$candidateCount'),
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRegenerate,
            icon: const RevericIcon(RevericIcons.arrow_clockwise, size: 13),
            label: Text(context.t(LocaleKeys.mapEditorStudioRegenerate)),
          ),
          const SizedBox(width: RevericSpacing.sm),
          FilledButton.icon(
            onPressed: onAdopt,
            icon: const RevericIcon(RevericIcons.check, size: 13),
            label: Text(context.t(LocaleKeys.mapEditorStudioAdopt)),
          ),
        ],
      ),
    );
  }
}

/// 左栏空列表的引导：一句话 + 一个动作，避免整块留黑。
class _RailEmptyHint extends StatelessWidget {
  const _RailEmptyHint({
    required this.text,
    required this.actionLabel,
    required this.onTap,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.md),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const RevericIcon(RevericIcons.add, size: 12),
            label: Text(actionLabel, style: typo.uiSmall),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({this.onOpenCartographer});

  /// 打开制图师；面板已打开时传 null，隐藏按钮避免重复入口。
  final VoidCallback? onOpenCartographer;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: 340,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RevericIcon(RevericIcons.map_outlined, size: 22),
          const SizedBox(height: RevericSpacing.md),
          Text(
            context.t(LocaleKeys.mapEditorStudioEmptyTitle),
            style: typo.uiSemibold,
          ),
          if (onOpenCartographer != null) ...[
            const SizedBox(height: RevericSpacing.lg),
            FilledButton.icon(
              onPressed: onOpenCartographer,
              icon: const RevericIcon(RevericIcons.explore, size: 14),
              label: Text(
                context.t(LocaleKeys.mapEditorStudioOpenCartographer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
