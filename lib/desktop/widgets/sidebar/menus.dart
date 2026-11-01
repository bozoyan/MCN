// 职责: 小说编辑侧边栏 — 处理文档、角色和条目的上下文菜单。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/common.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/screenplay.json
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/widgets/screenplay/labels.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
part of 'sidebar.dart';

extension _LeftSidebarMenus on _LeftSidebarState {
  void _showDocumentContextMenu(
    BuildContext context,
    TapDownDetails details,
    Document document,
  ) {
    final colors = RevericTheme.colorsOf(context);
    final isFolder = document.isFolder;
    final importItem = isFolder && widget.onImportDocument != null
        ? _buildImportFileMenuItem(context, document)
        : null;

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        ?importItem,
        if (isFolder && widget.onCreateFolder != null)
          RevericMenuItem(
            icon: _iconFolderPlus,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceNewFolder),
            onTap: () => _createFolderInParent(document.id),
          ),
        if (isFolder && widget.onCreateDocument != null)
          RevericMenuItem(
            icon: _iconNotePencil,
            iconColor: colors.accent,
            label: context.t(LocaleKeys.workspaceNewDocument),
            onTap: () => _createDocumentInParent(document.id),
          ),
        // 普通文档的标题在编辑器内修改，菜单只保留文件夹重命名和资料编辑。
        if (widget.onRenameDocument != null &&
            (isFolder || document.type == documentTypeMaterial))
          RevericMenuItem(
            icon: _iconPencilSimple,
            iconColor: colors.textSecondary,
            label: isFolder
                ? context.t(LocaleKeys.workspaceRenameFolder)
                : context.t(LocaleKeys.commonEdit),
            onTap: () => _showRenameDialog(context, document),
          ),
        if (widget.onDeleteDocument != null)
          RevericMenuItem(
            icon: _iconTrashSimple,
            iconColor: colors.warningText,
            labelColor: colors.warningText,
            label: context.t(LocaleKeys.commonDelete),
            onTap: () => _confirmDelete(context, document),
          ),
      ],
    );
  }

  void _createFolderInParent(String parentId) {
    if (widget.onCreateFolderInParent != null) {
      widget.onCreateFolderInParent!(parentId);
    }
  }

  void _createDocumentInParent(String parentId) {
    if (widget.onCreateDocumentInParent != null) {
      widget.onCreateDocumentInParent!(parentId);
    }
  }

  void _showRenameDialog(BuildContext context, Document document) {
    final colors = RevericTheme.colorsOf(context);
    final isFolder = document.isFolder;
    final isMaterial = document.type == documentTypeMaterial;

    showRevericDialog<void>(
      context: context,
      builder: (dialogContext) {
        return HookBuilder(
          builder: (dialogContext) {
            // 路由返回时关闭动画仍在使用输入框，controller 随弹窗卸载释放。
            final titleController = useTextEditingController(
              text: document.title,
            );
            final categoryController = useTextEditingController(
              text: document.category,
            );
            final titleError = useState<String?>(null);

            Future<void> submit() async {
              final newTitle = titleController.text.trim();
              if (newTitle.isEmpty) {
                titleError.value = dialogContext.t(LocaleKeys.formRequired);
                return;
              }
              if (widget.onRenameDocument == null) {
                Navigator.of(dialogContext).pop();
                return;
              }
              try {
                await widget.onRenameDocument!(
                  document.id,
                  newTitle,
                  category: isMaterial ? categoryController.text : null,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } on ArgumentError catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }
                titleError.value = error.message?.toString();
              } catch (_) {
                // 非校验错误已在 onRenameDocument 中记录 [DB] 日志。
              }
            }

            return RevericDialog(
              title: isFolder
                  ? context.t(LocaleKeys.workspaceRenameFolder)
                  : context.t(LocaleKeys.commonEdit),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RevericTextField(
                      controller: titleController,
                      autofocus: true,
                      label: isFolder
                          ? null
                          : context.t(LocaleKeys.commonTitle),
                      hintText: isFolder
                          ? context.t(LocaleKeys.workspaceNewFolderHint)
                          : context.t(LocaleKeys.workspaceEntryTitleHint),
                      errorText: titleError.value,
                      fillColor: colors.surfaceContainerHigh,
                      onChanged: (_) {
                        if (titleError.value != null) {
                          titleError.value = null;
                        }
                      },
                      onSubmitted: (_) => submit(),
                    ),
                    if (isMaterial) ...[
                      const SizedBox(height: RevericSpacing.x2l),
                      RevericTextField(
                        controller: categoryController,
                        label: context.t(
                          LocaleKeys.workspaceEntryCategoryLabel,
                        ),
                        hintText: context.t(
                          LocaleKeys.workspaceEntryCategoryMaterialsHint,
                        ),
                        fillColor: colors.surfaceContainerHigh,
                      ),
                    ],
                  ],
                ),
              ),
              width: 400,
              actions: [
                RevericButton.secondary(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                RevericButton.primary(
                  label: context.t(LocaleKeys.commonConfirm),
                  onPressed: submit,
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Document document) {
    final isFolder = document.isFolder;
    final title = document.title.isEmpty
        ? (isFolder
              ? context.t(LocaleKeys.sidebarUntitledFolder)
              : context.t(LocaleKeys.sidebarUntitledDocument))
        : document.title;

    unawaited(
      showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: isFolder
            ? context.t(
                LocaleKeys.sidebarDeleteFolderConfirm,
                namedArgs: {'title': title},
              )
            : context.t(
                LocaleKeys.sidebarDeleteDocumentConfirm,
                namedArgs: {'title': title},
              ),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
        onConfirm: () async {
          widget.onDeleteDocument?.call(document.id);
        },
      ),
    );
  }

  Widget _buildDeleteContextMenuWrapper(
    BuildContext context, {
    required Widget child,
    required String label,
    required NovelWorkspaceSection section,
    required String itemId,
  }) {
    if (widget.onDeleteItem == null) return child;
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showDeleteItemContextMenu(context, details, label, section, itemId);
      },
      child: child,
    );
  }

  void _showDeleteItemContextMenu(
    BuildContext context,
    TapDownDetails details,
    String label,
    NovelWorkspaceSection section,
    String itemId,
  ) {
    final colors = RevericTheme.colorsOf(context);

    showRevericContextMenu(
      context: context,
      position: details.globalPosition,
      entries: [
        RevericMenuItem(
          icon: _iconTrashSimple,
          iconColor: colors.warningText,
          labelColor: colors.warningText,
          label: context.t(LocaleKeys.commonDelete),
          onTap: () => _confirmDeleteItem(
            context,
            label: label,
            section: section,
            itemId: itemId,
          ),
        ),
      ],
    );
  }

  void _confirmDeleteItem(
    BuildContext context, {
    required String label,
    required NovelWorkspaceSection section,
    required String itemId,
  }) {
    final databasePath = widget.databasePath;
    final blockedReason =
        section == NovelWorkspaceSection.characters && databasePath != null
        ? screenplayInUseBlockedReason(
            context,
            introKey: LocaleKeys.screenplayCharacterInUse,
            references: ref
                .read(novelContentServiceProvider(databasePath))
                .getCharacterScreenplayScenes(itemId),
          )
        : null;
    unawaited(
      showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(
          LocaleKeys.sidebarDeleteDocumentConfirm,
          namedArgs: {'title': label},
        ),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
        blockedReason: blockedReason,
        onConfirm: () async {
          widget.onDeleteItem?.call(section, itemId);
        },
      ),
    );
  }

  RevericMenuItem? _buildImportFileMenuItem(
    BuildContext context,
    Document document,
  ) {
    final section = switch (document.type) {
      'worldbuilding' => NovelWorkspaceSection.lore,
      'material' => NovelWorkspaceSection.materials,
      _ => null,
    };
    if (section == null) return null;

    final colors = RevericTheme.colorsOf(context);

    return RevericMenuItem(
      icon: _iconFileText,
      iconColor: colors.accent,
      label: context.t(LocaleKeys.workspaceImportFile),
      onTap: () => widget.onImportDocument!(section, document.id),
    );
  }
}
