// 职责: 地图工作台的新建/编辑地点对话框
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/desktop/features/map/map_studio_page.dart
//   lib/desktop/features/map/maps_panel.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_select.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/maps_providers.dart';
import '../../../shared/services/maps_service.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/widgets/map/location_types.dart';
import '../../../shared/components/reveric_button.dart';

final _log = AppLogger.forModule('MapCreateDialogs');

/// 返回新建地点的 id；取消或失败返回 null。
Future<String?> showCreateLocationDialog(
  BuildContext context, {
  required String databasePath,
  required List<Location> locations,
  String? defaultParentId,
}) {
  return showRevericDialog<String>(
    context: context,
    builder: (_) => CreateLocationDialog(
      databasePath: databasePath,
      locations: locations,
      defaultParentId: defaultParentId,
    ),
  );
}

/// 地图与 world 一一对应时使用的受限入口：只创建无父级的 world，
/// 不向用户暴露普通地点的类型和父级字段。
Future<String?> showCreateWorldDialog(
  BuildContext context, {
  required String databasePath,
  required List<Location> locations,
}) {
  return showRevericDialog<String>(
    context: context,
    builder: (_) => CreateLocationDialog(
      databasePath: databasePath,
      locations: locations,
      worldOnly: true,
    ),
  );
}

class CreateLocationDialog extends HookConsumerWidget {
  const CreateLocationDialog({
    super.key,
    required this.databasePath,
    required this.locations,
    this.defaultParentId,
    this.worldOnly = false,
  });

  final String databasePath;
  final List<Location> locations;
  final String? defaultParentId;

  /// 当前地图产品只支持 world 级地图。由“创建地图”进入时固定创建 world，
  /// 避免用户误选其他地点类型后得到一个暂不支持的地图归属。
  final bool worldOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();
    final descriptionController = useTextEditingController();
    final selectedType = useState(
      worldOnly ? locationTypeWorld : locationTypeCity,
    );
    final selectedParent = useState<String?>(
      worldOnly ? null : defaultParentId,
    );
    final nameError = useState<String?>(null);
    final isSaving = useState(false);

    return RevericDialog.panel(
      title: Text(
        context.t(
          worldOnly
              ? LocaleKeys.mapEditorCreateWorldTitle
              : LocaleKeys.mapEditorCreateLocationTitle,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RevericTextField(
              controller: nameController,
              label: context.t(
                worldOnly
                    ? LocaleKeys.mapEditorWorldName
                    : LocaleKeys.commonName,
              ),
              hintText: context.t(
                worldOnly
                    ? LocaleKeys.mapEditorWorldNameHint
                    : LocaleKeys.mapEditorLocationNameHint,
              ),
              errorText: nameError.value,
            ),
            if (!worldOnly) ...[
              const SizedBox(height: RevericSpacing.lg),
              RevericSelect<String>(
                label: context.t(LocaleKeys.mapEditorStudioFieldType),
                value: selectedType.value,
                items: [
                  for (final type in mapLocationTypeOptions)
                    RevericSelectItem<String>(
                      value: type,
                      label: mapLocationTypeLabel(type, context),
                    ),
                ],
                onChanged: (type) => selectedType.value = type,
              ),
              const SizedBox(height: RevericSpacing.lg),
              RevericSelect<String>(
                label: context.t(LocaleKeys.mapEditorParentLocation),
                value: selectedParent.value ?? '',
                items: [
                  RevericSelectItem<String>(
                    value: '',
                    label: context.t(LocaleKeys.mapEditorNoParentLocation),
                  ),
                  for (final location in locations)
                    RevericSelectItem<String>(
                      value: location.id,
                      label: location.name,
                    ),
                ],
                onChanged: (value) {
                  selectedParent.value = value.isEmpty ? null : value;
                },
              ),
            ],
            const SizedBox(height: RevericSpacing.lg),
            RevericTextField(
              controller: descriptionController,
              label: context.t(LocaleKeys.commonDescription),
              hintText: context.t(
                worldOnly
                    ? LocaleKeys.mapEditorWorldDescriptionHint
                    : LocaleKeys.mapEditorLocationDescriptionHint,
              ),
              multiline: true,
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
      ),

      width: 400 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonCreate),
          onPressed: isSaving.value
              ? null
              : () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    nameError.value = context.t(
                      LocaleKeys.mapEditorLocationNameRequired,
                    );
                    return;
                  }

                  nameError.value = null;
                  isSaving.value = true;
                  try {
                    final service = ref.read(
                      locationsServiceProvider(databasePath),
                    );
                    final locationId = await service.createLocation(
                      name: name,
                      description: descriptionController.text.trim(),
                      type: selectedType.value,
                      parentId: selectedParent.value,
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop(locationId);
                    }
                  } catch (error, stackTrace) {
                    _log.error(
                      '[DB] location create failed: table=Locations '
                      'operation=INSERT type=${selectedType.value}',
                      error: error,
                      stackTrace: stackTrace,
                    );
                    if (context.mounted) {
                      nameError.value = context.t(
                        error is DuplicateLocationNameException
                            ? LocaleKeys.mapEditorLocationNameDuplicate
                            : LocaleKeys.commonSaveFailed,
                      );
                      isSaving.value = false;
                    }
                  }
                },
        ),
      ],
    );
  }
}

/// 返回是否发生了修改；取消返回 false。
Future<bool> showEditLocationDialog(
  BuildContext context, {
  required String databasePath,
  required List<Location> locations,
  required Location location,
}) {
  return showRevericDialog<bool>(
    context: context,
    builder: (_) => EditLocationDialog(
      databasePath: databasePath,
      locations: locations,
      location: location,
    ),
  ).then((value) => value ?? false);
}

class EditLocationDialog extends HookConsumerWidget {
  const EditLocationDialog({
    super.key,
    required this.databasePath,
    required this.locations,
    required this.location,
  });

  final String databasePath;
  final List<Location> locations;
  final Location location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController(text: location.name);
    final descriptionController = useTextEditingController(
      text: location.description,
    );
    final selectedType = useState(location.type);
    final selectedParent = useState<String?>(location.parentId);
    final nameError = useState<String?>(null);
    final isSaving = useState(false);

    // 上级候选排除自己；更深的循环引用由 service 的环形引用校验兜住。
    final parentOptions = [
      for (final candidate in locations)
        if (candidate.id != location.id) candidate,
    ];

    return RevericDialog.panel(
      title: Text(context.t(LocaleKeys.commonEdit)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RevericTextField(
              controller: nameController,
              label: context.t(LocaleKeys.commonName),
              hintText: context.t(LocaleKeys.mapEditorLocationNameHint),
              errorText: nameError.value,
            ),
            const SizedBox(height: RevericSpacing.lg),
            RevericSelect<String>(
              label: context.t(LocaleKeys.mapEditorStudioFieldType),
              value: selectedType.value,
              items: [
                for (final type in mapLocationTypeOptions)
                  RevericSelectItem<String>(
                    value: type,
                    label: mapLocationTypeLabel(type, context),
                  ),
              ],
              onChanged: (type) => selectedType.value = type,
            ),
            const SizedBox(height: RevericSpacing.lg),
            RevericSelect<String>(
              label: context.t(LocaleKeys.mapEditorParentLocation),
              value: selectedParent.value ?? '',
              items: [
                RevericSelectItem<String>(
                  value: '',
                  label: context.t(LocaleKeys.mapEditorNoParentLocation),
                ),
                for (final location in parentOptions)
                  RevericSelectItem<String>(
                    value: location.id,
                    label: location.name,
                  ),
              ],
              onChanged: (value) {
                selectedParent.value = value.isEmpty ? null : value;
              },
            ),
            const SizedBox(height: RevericSpacing.lg),
            RevericTextField(
              controller: descriptionController,
              label: context.t(LocaleKeys.commonDescription),
              hintText: context.t(LocaleKeys.mapEditorLocationDescriptionHint),
              multiline: true,
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
      ),

      width: 400 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonSave),
          onPressed: isSaving.value
              ? null
              : () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    nameError.value = context.t(
                      LocaleKeys.mapEditorLocationNameRequired,
                    );
                    return;
                  }

                  nameError.value = null;
                  isSaving.value = true;
                  try {
                    final service = ref.read(
                      locationsServiceProvider(databasePath),
                    );
                    await service.updateLocation(
                      id: location.id,
                      name: name,
                      description: descriptionController.text.trim(),
                      type: selectedType.value,
                      parentId: selectedParent.value,
                      clearParentId: selectedParent.value == null,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  } catch (error, stackTrace) {
                    _log.error(
                      '[DB] location edit failed: table=locations operation=UPDATE id=${location.id}',
                      error: error,
                      stackTrace: stackTrace,
                    );
                    if (context.mounted) {
                      nameError.value = context.t(
                        error is DuplicateLocationNameException
                            ? LocaleKeys.mapEditorLocationNameDuplicate
                            : LocaleKeys.commonSaveFailed,
                      );
                    }
                  } finally {
                    if (context.mounted) {
                      isSaving.value = false;
                    }
                  }
                },
        ),
      ],
    );
  }
}
