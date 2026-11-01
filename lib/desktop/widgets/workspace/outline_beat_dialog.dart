// 职责: Beat 编辑对话框 — 新增/编辑 timeline beat 的表单弹窗（元信息、短标题提示、章节步进、Markdown 正文）。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_editor.dart
//   lib/shared/models/outline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';

import '../../../shared/components/dialog_feedback.dart';
import '../../../shared/components/reveric_dropdowns.dart';
import '../../../shared/components/reveric_input_decoration.dart';
import '../../../shared/form/form.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/short_entity_id.dart';
import '../../../shared/utils/text_input_composing.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';

const EdgeInsets _beatMetaFieldPadding = EdgeInsets.symmetric(
  horizontal: RevericSpacing.lg,
  vertical: RevericSpacing.md,
);

enum BeatFormField<T> implements FieldSchema {
  title<String>(validators: [RequiredValidator<String>()]),
  content<String>(validators: [RequiredValidator<String>()]),
  status<String>(validators: [RequiredValidator<String>()]),
  chapterCount<String>(validators: [RequiredValidator<String>()]);

  const BeatFormField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class OutlineBeatDialog extends HookWidget {
  const OutlineBeatDialog({super.key, this.beat});

  final OutlineBeatDraft? beat;

  static const double _dialogMaxWidth = 720;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = beat;
    final contentController = useTextEditingController(
      text: current?.content ?? '',
    );
    final contentFocusNode = useFocusNode();
    // listen: false —— 标题字段用 notifyOnChange: true 驱动下面的实时预览，若这里还
    // listen，每敲一个字整个 dialog（含绑外部 controller 的 Markdown 编辑器）都会重建，
    // 正是 text-input-ime.md 里的失焦链路。notify 只交给那个 ListenableBuilder 消费。
    final form = useForm<BeatFormField>(
      listen: false,
      initialValues: {
        BeatFormField.title: current?.title ?? '',
        BeatFormField.content: current?.content ?? '',
        BeatFormField.status: current?.status ?? outlineStatusPending,
        BeatFormField.chapterCount: '${current?.chapterCount ?? 5}',
      },
    );

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        side: BorderSide(color: colors.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _dialogMaxWidth,
          maxHeight: maxHeight,
        ),
        child: DialogFeedback.intrinsic(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.x3l,
                  RevericSpacing.lg,
                  RevericSpacing.lg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        current == null
                            ? context.t(LocaleKeys.workspaceOutlineAddBeat)
                            : context.t(LocaleKeys.commonEdit),
                        style: typo.heading2.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.t(LocaleKeys.commonCancel),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: RevericIcon(
                        RevericIcons.close_rounded,
                        size: 20,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.borderSubtle),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(RevericSpacing.x4l),
                  child: HookedForm<BeatFormField>(
                    form: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: HookedFormField<BeatFormField, String>(
                                fieldHook: BeatFormField.status,
                                builder: (value, onChanged, error) {
                                  return _BeatStatusPicker(
                                    value: value ?? outlineStatusPending,
                                    onChanged: onChanged,
                                    label: context.t(LocaleKeys.commonStatus),
                                    errorText: error,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.lg),
                            Expanded(
                              child: HookedFormField<BeatFormField, String>(
                                fieldHook: BeatFormField.chapterCount,
                                builder: (value, onChanged, error) {
                                  return _BeatChapterCountField(
                                    value: value ?? '5',
                                    onChanged: (next) {
                                      onChanged?.call(next);
                                    },
                                    label: context.t(
                                      LocaleKeys
                                          .workspaceOutlineBeatChapterCountLabel,
                                    ),
                                    errorText: error,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RevericSpacing.x2l),
                        HookedTextFormField<BeatFormField>(
                          fieldHook: BeatFormField.title,
                          autofocus: current == null,
                          label: context.t(LocaleKeys.commonTitle),
                          hintText: context.t(
                            LocaleKeys.workspaceOutlineBeatTitleHint,
                          ),
                          notifyOnChange: true,
                        ),
                        ListenableBuilder(
                          listenable: form,
                          builder: (context, _) {
                            return _BeatTitlePreview(
                              title:
                                  form.getValue<String>(BeatFormField.title) ??
                                  '',
                            );
                          },
                        ),
                        const SizedBox(height: RevericSpacing.x2l),
                        Row(
                          children: [
                            Text(
                              context.t(LocaleKeys.commonContent),
                              style: typo.uiSemibold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _insertContentTemplate(
                                context: context,
                                controller: contentController,
                                form: form,
                                focusNode: contentFocusNode,
                              ),
                              icon: const RevericIcon(
                                RevericIcons.format_list_bulleted,
                                size: 16,
                              ),
                              label: Text(
                                context.t(
                                  LocaleKeys.workspaceOutlineBeatInsertTemplate,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RevericSpacing.sm),
                        HookedFormField<BeatFormField, String>(
                          fieldHook: BeatFormField.content,
                          builder: (value, onChanged, error) {
                            return SizedBox(
                              height: 360,
                              child: RevericMarkdownEditor(
                                controller: contentController,
                                focusNode: contentFocusNode,
                                hintText: context.t(
                                  LocaleKeys.workspaceOutlineBeatContentHint,
                                ),
                                errorText: error,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: colors.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(RevericSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.t(LocaleKeys.commonCancel)),
                    ),
                    const SizedBox(width: RevericSpacing.sm),
                    FilledButton(
                      onPressed: () => _submitBeat(
                        context: context,
                        form: form,
                        current: current,
                        contentController: contentController,
                      ),
                      child: Text(context.t(LocaleKeys.commonSave)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _insertContentTemplate({
  required BuildContext context,
  required TextEditingController controller,
  required FormFieldsController<BeatFormField> form,
  required FocusNode focusNode,
}) {
  final template = context.t(LocaleKeys.workspaceOutlineBeatContentTemplate);
  final existing = controller.text.trim();
  if (existing.isNotEmpty) {
    controller.text = '$existing\n\n$template';
  } else {
    controller.text = template;
  }
  form.updateValue(BeatFormField.content, controller.text, notify: true);
  focusNode.requestFocus();
  controller.selection = TextSelection.collapsed(
    offset: controller.text.length,
  );
}

void _submitBeat({
  required BuildContext context,
  required FormFieldsController<BeatFormField> form,
  required OutlineBeatDraft? current,
  required TextEditingController contentController,
}) {
  syncFormFieldsFromControllersBeforeValidate(
    form: form,
    fields: {BeatFormField.content: contentController},
  );
  if (!form.validate()) {
    return;
  }
  final rawCount = (form.getValue<String>(BeatFormField.chapterCount) ?? '5')
      .trim();
  final parsedCount = int.tryParse(rawCount) ?? 5;
  if (parsedCount < 1) {
    form.setError(
      BeatFormField.chapterCount,
      context.t(
        LocaleKeys.workspaceOutlineBeatChapterCountMin,
        namedArgs: {'min': '1'},
      ),
    );
    return;
  }
  Navigator.of(context).pop(
    (current ??
            OutlineBeatDraft(
              id: buildShortEntityId(ShortEntityIdType.outlineBeat),
              isNew: true,
            ))
        .copyWith(
          title: form.getValue<String>(BeatFormField.title) ?? '',
          content: form.getValue<String>(BeatFormField.content) ?? '',
          status:
              form.getValue<String>(BeatFormField.status) ??
              outlineStatusPending,
          chapterCount: parsedCount,
        ),
  );
}

class _BeatTitlePreview extends StatelessWidget {
  const _BeatTitlePreview({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    final shortTitle = shortOutlineBeatTitle(trimmed);
    if (shortTitle.isEmpty || shortTitle == trimmed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: RevericSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(LocaleKeys.workspaceOutlineBeatCardPreviewLabel),
              style: typo.uiTiny.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              shortTitle,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatChapterCountField extends HookWidget {
  const _BeatChapterCountField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.errorText,
  });

  final String value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final count = int.tryParse(value.trim()) ?? 5;
    final controller = useTextEditingController(text: value);

    useEffect(() {
      if (controller.text != value) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
      return null;
    }, [controller, value]);

    return InputDecorator(
      decoration: revericInputDecoration(
        context,
        label: label,
        errorText: errorText,
        contentPadding: _beatMetaFieldPadding,
      ),
      child: Row(
        children: [
          _ChapterStepperButton(
            tooltip: context.t(
              LocaleKeys.workspaceOutlineBeatChapterCountDecrease,
            ),
            icon: RevericIcons.remove,
            onPressed: count > 1
                ? () {
                    onChanged('${count - 1}');
                  }
                : null,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: onChanged,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintText: '$count',
                hintStyle: typo.uiSemibold.copyWith(color: colors.textSubtle),
              ),
            ),
          ),
          _ChapterStepperButton(
            tooltip: context.t(
              LocaleKeys.workspaceOutlineBeatChapterCountIncrease,
            ),
            icon: RevericIcons.add,
            onPressed: count < 999
                ? () {
                    onChanged('${count + 1}');
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _ChapterStepperButton extends StatelessWidget {
  const _ChapterStepperButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final String icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.sm,
            vertical: RevericSpacing.xs,
          ),
          child: RevericIcon(
            icon,
            size: 16,
            color: disabled ? colors.textSubtle : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _BeatStatusPicker extends StatelessWidget {
  const _BeatStatusPicker({
    required this.value,
    required this.onChanged,
    this.label,
    this.errorText,
  });

  final String value;
  final void Function(String?)? onChanged;
  final String? label;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final normalized = outlineStatuses.contains(value)
        ? value
        : outlineStatusPending;

    return RevericFormDropdown<String>(
      value: normalized,
      contentPadding: _beatMetaFieldPadding,
      items: outlineStatuses.map((status) {
        return DropdownMenuItem<String>(
          value: status,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor(context, status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                statusLabel(context, status),
                style: typo.ui.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
      label: label,
      errorText: errorText,
      selectedItemBuilder: (context) {
        return outlineStatuses.map((status) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor(context, status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                statusLabel(context, status),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
          );
        }).toList();
      },
    );
  }
}

String statusLabel(BuildContext context, String status) {
  return switch (status) {
    outlineStatusInProgress => context.t(
      LocaleKeys.workspaceOutlineStatusInProgress,
    ),
    outlineStatusFinished => context.t(
      LocaleKeys.workspaceOutlineStatusFinished,
    ),
    _ => context.t(LocaleKeys.workspaceOutlineStatusPending),
  };
}

Color statusColor(BuildContext context, String status) {
  final colors = RevericTheme.colorsOf(context);
  return switch (status) {
    outlineStatusInProgress => colors.accent,
    outlineStatusFinished => colors.accentWarm,
    _ => colors.warningText,
  };
}
