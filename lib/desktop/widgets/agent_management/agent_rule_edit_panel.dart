// 职责: AgentRule 编辑面板 — 提供编辑、启用/禁用 AgentRule 的界面（删除走侧栏右键菜单）
// 关联文件:
//   lib/shared/models/agent_rule.dart
//   lib/shared/models/novel_workspace.dart
//   lib/shared/providers/agent_rule_providers.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/components/reveric_switch.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_rule.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/providers/agent_rule_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/text_input_composing.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../third/form/flutter_hook_form.dart';
import '../desktop_window_frame.dart';
import 'agent_edit_save_contract.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';

class AgentRuleEditPanel extends HookConsumerWidget {
  const AgentRuleEditPanel({
    super.key,
    required this.rule,
    this.databasePath,
    this.headerLeadingInset = 0,
    this.headerTrailingInset = 0,
    this.headerGestureExclusionKey,
    required this.onSaved,
    this.onCancel,
    this.onBack,
    this.onHasChangesChanged,
    this.onRegisterSave,
    this.onRegisterHasChanges,
    this.onRegisterIsBlankCreateDraft,
    this.onSaveRule,
    this.onRuleSaved,
  });

  final AgentRule rule;
  final String? databasePath;
  final double headerLeadingInset;
  final double headerTrailingInset;
  final GlobalKey? headerGestureExclusionKey;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onHasChangesChanged;

  /// 向父级注册「保存当前编辑」的函数（返回是否保存成功），用于未保存变更
  /// 拦截 dialog 的「保存」按钮。组件卸载时回传 null 注销。
  final ValueChanged<Future<bool> Function()?>? onRegisterSave;

  /// 向父级注册同步读取当前编辑态的函数，用于用户快速点击导航按钮时不依赖
  /// post-frame dirty 上报。
  final ValueChanged<bool Function()?>? onRegisterHasChanges;

  /// 向父级注册当前新建草稿是否为空的函数；空草稿离开时直接放弃，不弹窗。
  final ValueChanged<bool Function()?>? onRegisterIsBlankCreateDraft;

  /// 由父级执行实际持久化，并返回保存后的 rule。
  final AgentRuleEditSaver? onSaveRule;

  /// 保存成功后把实际持久化的 rule 回传给父级，让父级 selection 也推进到
  /// 已保存状态；否则离开确认 dialog 的保存路径只会更新子组件局部状态。
  final ValueChanged<AgentRule>? onRuleSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final editorHeight = MediaQuery.sizeOf(context).height * 0.6;
    final savedRuleOverride = useState<AgentRule?>(null);
    final effectiveRule = () {
      final override = savedRuleOverride.value;
      if (override != null && override.id == rule.id) {
        return override;
      }
      return rule;
    }();

    useEffect(() {
      savedRuleOverride.value = null;
      return null;
    }, [rule.id, rule.updatedAt]);

    // keys 中加入 updatedAt：保存成功后先用本地快照推进基线，后续 provider
    // 回流最新 rule 时再切回外部数据；updatedAt 变化会触发 useForm 重建，
    // 从而把 form.hasChanged 复位，避免一直误报未保存变更。
    final form = useForm<AgentRuleEditFields>(
      initialValues: {
        AgentRuleEditFields.name: effectiveRule.name,
        AgentRuleEditFields.content: effectiveRule.content,
        AgentRuleEditFields.enabled: effectiveRule.enabled,
      },
      keys: [effectiveRule.id, effectiveRule.updatedAt],
      listen: false,
    );

    final nameController = useTextEditingController(text: effectiveRule.name);
    final nameFocusNode = useFocusNode();
    final contentController = useTextEditingController(
      text: effectiveRule.content,
    );
    final contentFocusNode = useFocusNode();
    final isSaving = useState(false);
    final hasEdits = useState(false);
    final enabledValue = useState(effectiveRule.enabled);
    final syncingControllersRef = useRef(false);

    bool computeHasEdits() {
      return nameController.text != effectiveRule.name ||
          contentController.text != effectiveRule.content ||
          enabledValue.value != effectiveRule.enabled;
    }

    bool isBlankCreateDraft() {
      return effectiveRule.id.startsWith('__new__') &&
          nameController.text.trim().isEmpty &&
          contentController.text.trim().isEmpty;
    }

    void notifyDirtyIfNeeded({
      required FocusNode focusToPreserve,
      TextEditingController? composingController,
    }) {
      notifyDirtyAfterExternalControllerEdit(
        focusToPreserve: focusToPreserve,
        suppress: syncingControllersRef.value,
        composingController: composingController,
        computeHasEdits: computeHasEdits,
        readHasEdits: () => hasEdits.value,
        writeHasEdits: (next) => hasEdits.value = next,
        onHasChangesChanged: onHasChangesChanged,
      );
    }

    // 注册「保存当前编辑」给父级（未保存变更拦截 dialog 用）。saveRef 每次
    // build 更新为最新的 save 闭包，注册的包装函数始终调用最新闭包。
    // 只在挂载时注册一次、卸载时注销：父级每次 build 都会重建 onRegisterSave
    // 闭包，若把它放进 keys 会触发「注销→重注册」抖动，且 hooks 会在新 setup
    // 之后才跑旧 cleanup，最终停在注销（null）上，导致父级拿不到保存函数。
    final onRegisterSaveRef = useRef(onRegisterSave);
    onRegisterSaveRef.value = onRegisterSave;
    final onRegisterHasChangesRef = useRef(onRegisterHasChanges);
    onRegisterHasChangesRef.value = onRegisterHasChanges;
    final onRegisterIsBlankCreateDraftRef = useRef(
      onRegisterIsBlankCreateDraft,
    );
    onRegisterIsBlankCreateDraftRef.value = onRegisterIsBlankCreateDraft;
    final saveRef = useRef<Future<bool> Function()?>(null);
    final hasChangesRef = useRef<bool Function()?>(null);
    final isBlankCreateDraftRef = useRef<bool Function()?>(null);
    useEffect(() {
      onRegisterSaveRef.value?.call(
        () async => await saveRef.value?.call() ?? false,
      );
      onRegisterHasChangesRef.value?.call(
        () => hasChangesRef.value?.call() ?? false,
      );
      onRegisterIsBlankCreateDraftRef.value?.call(
        () => isBlankCreateDraftRef.value?.call() ?? false,
      );
      return () {
        onRegisterSaveRef.value?.call(null);
        onRegisterHasChangesRef.value?.call(null);
        onRegisterIsBlankCreateDraftRef.value?.call(null);
      };
    }, const []);

    useEffect(() {
      syncingControllersRef.value = true;
      nameController.text = effectiveRule.name;
      contentController.text = effectiveRule.content;
      enabledValue.value = effectiveRule.enabled;
      form.updateValue(
        AgentRuleEditFields.enabled,
        effectiveRule.enabled,
        notify: false,
      );
      syncingControllersRef.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        hasEdits.value = false;
        onHasChangesChanged?.call(false);
      });
      return null;
    }, [effectiveRule.id, effectiveRule.updatedAt]);

    final nameForDuplicateCheck = useState('');

    useEffect(() {
      void onNameChanged() {
        if (isTextInputComposing(nameController)) {
          return;
        }
        nameForDuplicateCheck.value = nameController.text;
        notifyDirtyIfNeeded(
          focusToPreserve: nameFocusNode,
          composingController: nameController,
        );
      }

      nameController.addListener(onNameChanged);
      return () => nameController.removeListener(onNameChanged);
    }, [nameController, nameFocusNode]);

    useEffect(() {
      void onContentChanged() {
        notifyDirtyIfNeeded(
          focusToPreserve: contentFocusNode,
          composingController: contentController,
        );
      }

      contentController.addListener(onContentChanged);
      return () => contentController.removeListener(onContentChanged);
    }, [contentController, contentFocusNode]);

    final existingRules = databasePath != null
        ? ref.watch(agentRulesStreamProvider(databasePath!)).value ?? []
        : <AgentRule>[];

    bool isNameDuplicate(String name) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return false;
      return existingRules.any(
        (r) => r.name == trimmed && r.id != effectiveRule.id,
      );
    }

    final debouncedName = useDebounced(
      nameForDuplicateCheck.value,
      const Duration(milliseconds: 400),
    );
    final isNameDuplicateLive = useState(false);

    useEffect(() {
      if (debouncedName == null) return null;
      final name = debouncedName;
      if (name.isEmpty || name == effectiveRule.name) {
        isNameDuplicateLive.value = false;
        return null;
      }
      isNameDuplicateLive.value = existingRules.any(
        (r) => r.name == name && r.id != effectiveRule.id,
      );
      return null;
    }, [debouncedName, existingRules, effectiveRule]);

    useEffect(() {
      isNameDuplicateLive.value = false;
      return null;
    }, [effectiveRule.id]);

    final canDragRuleReference =
        databasePath != null &&
        !hasEdits.value &&
        effectiveRule.name.trim().isNotEmpty;

    // 仅负责持久化，返回是否保存成功；不做导航。导航由调用方（header 保存按钮
    // 成功后 onSaved，或父级拦截 dialog）处理。
    Future<bool> save() async {
      syncFormFieldsFromControllersBeforeValidate(
        form: form,
        fields: {
          AgentRuleEditFields.name: nameController,
          AgentRuleEditFields.content: contentController,
        },
      );
      if (!form.validate()) return false;

      final name = nameController.text.trim();
      final content = contentController.text.trim();
      final enabledFieldValue = enabledValue.value;

      if (content.length > agentRuleLongContentWarningThreshold) {
        final shouldSave = await showConfirmDialog(
          context,
          title: context.t(LocaleKeys.agentRuleTitle),
          message: context.t(
            LocaleKeys.agentRuleContentLongHint,
            namedArgs: {'threshold': '$agentRuleLongContentWarningThreshold'},
          ),
          confirmLabel: context.t(LocaleKeys.commonSave),
          variant: ConfirmDialogVariant.warning,
        );
        if (!shouldSave || !context.mounted) {
          return false;
        }
      }

      if (isNameDuplicate(name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                LocaleKeys.agentRuleDuplicateName,
                namedArgs: {'name': name},
              ),
            ),
          ),
        );
        return false;
      }

      isSaving.value = true;
      try {
        final draft = AgentRuleEditDraft(
          original: effectiveRule,
          name: name,
          content: content,
          enabled: enabledFieldValue,
        );

        final savedRule =
            await onSaveRule?.call(draft) ??
            draft.toRule(updatedAt: DateTime.now());

        savedRuleOverride.value = savedRule;
        onRuleSaved?.call(savedRule);
        hasEdits.value = false;
        onHasChangesChanged?.call(false);
        return true;
      } on AgentRuleNameConflictException catch (e) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                LocaleKeys.agentRuleDuplicateName,
                namedArgs: {'name': e.name},
              ),
            ),
          ),
        );
        return false;
      } finally {
        isSaving.value = false;
      }
    }

    saveRef.value = save;
    hasChangesRef.value = computeHasEdits;
    isBlankCreateDraftRef.value = isBlankCreateDraft;

    Future<void> saveFromHeader() async {
      if (await save()) {
        onSaved();
      }
    }

    final hasChanges = computeHasEdits();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHasChangesChanged?.call(hasChanges);
      });
      return null;
    }, [hasChanges, effectiveRule.id]);

    return Container(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context,
            title: effectiveRule.name.isEmpty
                ? context.t(LocaleKeys.commonUntitled)
                : effectiveRule.name,
            hasChanges: hasChanges,
            isSaving: isSaving.value,
            enabled: enabledValue.value,
            onBack: onBack,
            onToggleEnabled: (v) {
              enabledValue.value = v;
              form.updateValue(AgentRuleEditFields.enabled, v, notify: false);
              notifyDirtyIfNeeded(focusToPreserve: nameFocusNode);
            },
            onSave: saveFromHeader,
          ),
          Divider(height: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x6l,
                RevericSpacing.x4l,
                RevericSpacing.x6l,
                RevericSpacing.x6l,
              ),
              child: HookedForm(
                form: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AgentRuleReferenceHint(
                      rule: effectiveRule,
                      canDrag: canDragRuleReference,
                    ),
                    const SizedBox(height: RevericSpacing.x4l),
                    _buildFieldLabel(context, LocaleKeys.agentRuleName),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<AgentRuleEditFields, String>(
                      fieldHook: AgentRuleEditFields.name,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? context.t(LocaleKeys.agentRuleNameRequired)
                          : null,
                      builder: (value, onChanged, error) {
                        return RevericTextField(
                          controller: nameController,
                          focusNode: nameFocusNode,
                          errorText: error,
                        );
                      },
                    ),
                    if (isNameDuplicateLive.value) ...[
                      const SizedBox(height: RevericSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: RevericSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            RevericIcon(
                              RevericIcons.warning_amber_rounded,
                              size: 14,
                              color: colors.warningText,
                            ),
                            const SizedBox(width: RevericSpacing.xs),
                            Expanded(
                              child: Text(
                                context.t(
                                  LocaleKeys.agentRuleDuplicateName,
                                  namedArgs: {
                                    'name': nameController.text.trim(),
                                  },
                                ),
                                style: typo.uiSmall.copyWith(
                                  color: colors.warningText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: RevericSpacing.x2l),
                    _buildFieldLabel(context, LocaleKeys.agentRuleContent),
                    const SizedBox(height: RevericSpacing.sm),
                    HookedFormField<AgentRuleEditFields, String>(
                      fieldHook: AgentRuleEditFields.content,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return context.t(LocaleKeys.agentRuleContentRequired);
                        }
                        return null;
                      },
                      builder: (value, onChanged, error) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: editorHeight,
                              child: RevericMarkdownEditor(
                                controller: contentController,
                                focusNode: contentFocusNode,
                                hintText: context.t(
                                  LocaleKeys.agentRuleContentHint,
                                ),
                                limitPasteSize: false,
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: RevericSpacing.xs),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: RevericSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    RevericIcon(
                                      RevericIcons.warning_amber_rounded,
                                      size: 14,
                                      color: colors.warningText,
                                    ),
                                    const SizedBox(width: RevericSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: typo.uiSmall.copyWith(
                                          color: colors.warningText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String title,
    required bool hasChanges,
    required bool isSaving,
    required bool enabled,
    required VoidCallback? onBack,
    required ValueChanged<bool> onToggleEnabled,
    required VoidCallback onSave,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      height: DesktopWindowFrame.titleBarHeight,
      padding: EdgeInsets.only(
        left: RevericSpacing.x2l + headerLeadingInset,
        right: RevericSpacing.x2l + headerTrailingInset,
      ),
      color: colors.surfaceContainer,
      child: KeyedSubtree(
        key: headerGestureExclusionKey,
        child: Row(
          children: [
            if (onBack != null) ...[
              Tooltip(
                message: MaterialLocalizations.of(context).backButtonTooltip,
                child: InkWell(
                  key: const Key('agent_rule_edit_back'),
                  onTap: onBack,
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                  hoverColor: colors.hover,
                  child: Padding(
                    padding: const EdgeInsets.all(RevericSpacing.xs),
                    child: RevericIcon(
                      RevericIcons.chevron_left,
                      size: 18,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.xs),
            ],
            Expanded(
              child: Row(
                children: [
                  Text(
                    context.t(LocaleKeys.agentRuleTitle),
                    style: typo.ui.copyWith(color: colors.textMuted),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.xs,
                    ),
                    child: Text(
                      '>',
                      style: typo.ui.copyWith(color: colors.textSubtle),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      title,
                      style: typo.uiMedium.copyWith(color: colors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              context.t(LocaleKeys.agentRuleEnabled),
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: RevericSpacing.xs),
            RevericSwitch(value: enabled, onChanged: onToggleEnabled),
            const SizedBox(width: RevericSpacing.md),
            if (onCancel != null) ...[
              TextButton(
                onPressed: hasChanges ? onCancel : null,
                child: Text(context.t(LocaleKeys.commonCancel)),
              ),
              const SizedBox(width: RevericSpacing.sm),
            ],
            FilledButton(
              onPressed: isSaving || !hasChanges ? null : onSave,
              child: Text(
                isSaving
                    ? context.t(LocaleKeys.commonSaving)
                    : context.t(LocaleKeys.commonSave),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(BuildContext context, String localeKey) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Text(
      context.t(localeKey),
      style: typo.uiSemibold.copyWith(color: colors.textSecondary),
    );
  }
}

class _AgentRuleReferenceHint extends StatelessWidget {
  const _AgentRuleReferenceHint({required this.rule, required this.canDrag});

  final AgentRule rule;
  final bool canDrag;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final child = _AgentRuleReferenceHintSurface(
      text: context.t(LocaleKeys.agentRuleNextChatHint),
      trailingText: canDrag
          ? null
          : context.t(LocaleKeys.agentRuleSaveBeforeDragHint),
    );

    final reference = AiContextReference(
      kind: AiContextReferenceKind.agent_rule,
      section: NovelWorkspaceSection.overview,
      itemId: rule.id,
      label: rule.name,
    );

    return Draggable<AiContextReference>(
      maxSimultaneousDrags: canDrag ? 1 : 0,
      data: reference,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(color: colors.accent),
            boxShadow: [
              BoxShadow(
                color: colors.textPrimary.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.rule_outlined,
                size: 14,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                rule.name,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: child),
      child: child,
    );
  }
}

class _AgentRuleReferenceHintSurface extends StatelessWidget {
  const _AgentRuleReferenceHintSurface({
    required this.text,
    required this.trailingText,
  });

  final String text;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericIcon(
            RevericIcons.rule_outlined,
            size: 18,
            color: colors.accent,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: typo.uiSmall.copyWith(
                    color: colors.textPrimary,
                    height: 1.35,
                  ),
                ),
                if (trailingText != null) ...[
                  const SizedBox(height: RevericSpacing.xs),
                  Text(
                    trailingText!,
                    style: typo.uiTiny.copyWith(
                      color: colors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
