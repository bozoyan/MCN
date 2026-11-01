// 职责: 画布列表面板 — 展示当前小说的所有画布，支持新建/重命名/删除，点击打开工作区画布
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/novel_workspace.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/error-handling.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/components/reveric_text_field.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/providers/canvas_providers.dart';
import '../../../../shared/services/canvas_service.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/components/reveric_dialog.dart';
import '../../../../shared/components/reveric_button.dart';

/// 画布名写入失败时的输入框提示文案。
///
/// 画布名是 AI 路径 `/canvas/{name}` 的键，重名和特殊字符（? /）都会被 service
/// 拒绝；这些失败是用户改个名字就能解决的，走输入框内联报错而不是全局 toast。
String _canvasNameErrorText(
  BuildContext context,
  CanvasServiceException error,
) {
  return switch (error.errorCode) {
    'duplicate_name' => context.t(LocaleKeys.canvasNameDuplicate),
    'invalid_name' => context.t(LocaleKeys.commonNameHasPathChar),
    _ => error.message,
  };
}

/// 画布列表面板：嵌入左侧栏 Middle Column，与 chapters/characters 列表同级。
///
/// - 新建画布：弹窗输入名称 → `CanvasService.createCanvas` → onOpenCanvas 打开工作区画布。
/// - 点击画布：通过 onOpenCanvas 打开工作区画布。
/// - 右键菜单：重命名 / 删除(软删)。
class CanvasListPanel extends ConsumerWidget {
  const CanvasListPanel({
    super.key,
    required this.databasePath,
    required this.novelId,
    required this.onOpenCanvas,
    this.selectedCanvasId,
    this.novelName,
    this.novelDescription,
  });

  final String databasePath;
  final String novelId;

  /// 打开普通画布 —— 由宿主切工作区 selection，把画布渲染进主内容区。
  final ValueChanged<String> onOpenCanvas;

  /// 当前在主内容区打开的画布 id，用于列表高亮。
  final String? selectedCanvasId;
  final String? novelName;
  final String? novelDescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvasesAsync = ref.watch(canvasesProvider(databasePath));

    return canvasesAsync.when(
      data: (canvases) => _CanvasListContent(
        canvases: canvases,
        databasePath: databasePath,
        novelId: novelId,
        novelName: novelName,
        novelDescription: novelDescription,
        onOpenCanvas: onOpenCanvas,
        selectedCanvasId: selectedCanvasId,
        ref: ref,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CanvasListError(error: error),
    );
  }
}

class _CanvasListContent extends StatelessWidget {
  const _CanvasListContent({
    required this.canvases,
    required this.databasePath,
    required this.novelId,
    required this.novelName,
    required this.novelDescription,
    required this.onOpenCanvas,
    required this.selectedCanvasId,
    required this.ref,
  });

  final List<CanvasEntry> canvases;
  final String databasePath;
  final String novelId;
  final String? novelName;
  final String? novelDescription;
  final ValueChanged<String> onOpenCanvas;
  final String? selectedCanvasId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: RevericSpacing.sm),
      children: [
        _buildHeader(context),
        ...canvases.map((canvas) => _buildCanvasItem(context, canvas)),
        if (canvases.isEmpty) _buildEmptyHint(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: RevericSpacing.x2l,
        right: RevericSpacing.sm,
        top: RevericSpacing.xs,
        bottom: RevericSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.t(LocaleKeys.canvasTitle),
              style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            '${canvases.length}',
            style: typo.uiTiny.copyWith(color: colors.textSubtle),
          ),
          const SizedBox(width: RevericSpacing.xs),
          InkWell(
            onTap: () => _showCreateDialog(context),
            borderRadius: BorderRadius.circular(RevericRadius.small),
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.xs),
              child: RevericIcon(
                RevericIcons.add,
                size: 16,
                color: colors.textSubtle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasItem(BuildContext context, CanvasEntry canvas) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final isSelected = canvas.id == selectedCanvasId;
    final child = Material(
      color: isSelected ? colors.selected : Colors.transparent,
      child: InkWell(
        onTap: () => onOpenCanvas(canvas.id),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.only(
            left: RevericSpacing.x2l,
            right: RevericSpacing.x2l,
            top: RevericSpacing.xs,
            bottom: RevericSpacing.xs,
          ),
          child: Row(
            children: [
              RevericIcon(
                RevericIcons.frame_corners,
                size: 16,
                color: colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  canvas.name.isEmpty
                      ? context.t(LocaleKeys.canvasTitle)
                      : canvas.name,
                  style: typo.ui.copyWith(
                    color: isSelected
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details, canvas),
      child: child,
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.lg,
      ),
      child: Text(
        context.t(LocaleKeys.canvasEmptyHint),
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? nameError;

    showRevericDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return RevericDialog.panel(
              title: Text(context.t(LocaleKeys.commonCreate)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RevericTextField(
                      controller: nameController,
                      autofocus: true,
                      label: context.t(LocaleKeys.canvasNameHint),
                      errorText: nameError,
                      onChanged: (_) {
                        if (nameError != null) {
                          setDialogState(() {
                            nameError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                    RevericTextField(
                      controller: descriptionController,
                      label: context.t(LocaleKeys.canvasDescriptionHint),
                      multiline: true,
                      minLines: 3,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              width: 400 + RevericSpacing.x4l * 2,

              actions: [
                RevericButton.secondary(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                RevericButton.primary(
                  label: context.t(LocaleKeys.commonCreate),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        nameError = context.t(LocaleKeys.canvasNameRequired);
                      });
                      return;
                    }
                    final service = ref.read(
                      canvasServiceProvider(databasePath),
                    );
                    final String id;
                    try {
                      id = await service.createCanvas(
                        name: name,
                        description: descriptionController.text.trim(),
                      );
                    } on CanvasServiceException catch (error) {
                      setDialogState(() {
                        nameError = _canvasNameErrorText(dialogContext, error);
                      });
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                      onOpenCanvas(id);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, CanvasEntry canvas) {
    final nameController = TextEditingController(text: canvas.name);
    final descriptionController = TextEditingController(
      text: canvas.description,
    );
    String? nameError;

    showRevericDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return RevericDialog.panel(
              title: Text(context.t(LocaleKeys.canvasRenameCanvas)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RevericTextField(
                      controller: nameController,
                      autofocus: true,
                      label: context.t(LocaleKeys.canvasNameHint),
                      errorText: nameError,
                      onChanged: (_) {
                        if (nameError != null) {
                          setDialogState(() {
                            nameError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                    RevericTextField(
                      controller: descriptionController,
                      label: context.t(LocaleKeys.canvasDescriptionHint),
                      multiline: true,
                      minLines: 3,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              width: 400 + RevericSpacing.x4l * 2,

              actions: [
                RevericButton.secondary(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                RevericButton.primary(
                  label: context.t(LocaleKeys.commonSave),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        nameError = context.t(LocaleKeys.canvasNameRequired);
                      });
                      return;
                    }
                    final service = ref.read(
                      canvasServiceProvider(databasePath),
                    );
                    try {
                      await service.renameCanvas(
                        canvasId: canvas.id,
                        name: name,
                      );
                    } on CanvasServiceException catch (error) {
                      setDialogState(() {
                        nameError = _canvasNameErrorText(dialogContext, error);
                      });
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    CanvasEntry canvas,
  ) async {
    final colors = RevericTheme.colorsOf(context);
    await showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        RevericMenuItem(
          icon: RevericIcons.edit_outlined,
          iconColor: colors.accent,
          label: context.t(LocaleKeys.canvasRenameCanvas),
          onTap: () {
            if (context.mounted) {
              _showRenameDialog(context, canvas);
            }
          },
        ),
        RevericMenuItem(
          icon: RevericIcons.delete_outline,
          iconColor: colors.deletionBorder,
          labelColor: colors.deletionBorder,
          label: context.t(LocaleKeys.commonDelete),
          onTap: () async {
            if (!context.mounted) {
              return;
            }
            final confirmed = await showConfirmDialog(
              context,
              title: context.t(LocaleKeys.commonDelete),
              message: context.t(LocaleKeys.canvasDeleteConfirm),
              confirmLabel: context.t(LocaleKeys.commonDelete),
              variant: ConfirmDialogVariant.warning,
            );
            if (!confirmed) {
              return;
            }
            if (!context.mounted) {
              return;
            }
            await ref
                .read(canvasServiceProvider(databasePath))
                .softDeleteCanvas(canvas.id);
          },
        ),
      ],
    );
  }
}

class _CanvasListError extends StatelessWidget {
  const _CanvasListError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.all(RevericSpacing.md),
      child: Text(
        '$error',
        style: typo.uiSmall.copyWith(color: colors.deletionBorder),
      ),
    );
  }
}
