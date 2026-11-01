// 职责: 风格库弹层的编辑态 — 编辑并保存自定义风格的名称与前后缀提示词，离开前确认放弃未保存修改。
// 关联文件:
//   lib/desktop/features/production/style_picker.dart
//   lib/shared/providers/production_media.dart
//   lib/shared/services/production/style_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/form/form.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/production/style.dart';
import '../../../shared/providers/production_media.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';

final _log = AppLogger.forModule('Production');

enum _StyleField<T> implements FieldSchema {
  name<String>(),
  before<String>(),
  after<String>();

  const _StyleField();
  @override
  List<Validator<dynamic>>? get validators => null;
}

class ProductionStyleEditor extends HookConsumerWidget {
  const ProductionStyleEditor({
    super.key,
    required this.onClose,
    required this.onDismiss,
    this.style,
  });

  /// null 时新建。
  final ProductionStyleRow? style;

  /// 回到风格列表。
  final VoidCallback onClose;

  /// 关闭整个风格库弹层。
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = useForm<_StyleField>(
      initialValues: {
        _StyleField.name: style?.name ?? '',
        _StyleField.before: style?.before ?? '',
        _StyleField.after: style?.after ?? '',
      },
    );
    final busy = useState(false), failed = useState(false);
    final service = ref.watch(productionStyleServiceProvider);
    String value(_StyleField field) => form.getValue<String>(field) ?? '';
    bool dirty() =>
        value(_StyleField.name) != (style?.name ?? '') ||
        value(_StyleField.before) != (style?.before ?? '') ||
        value(_StyleField.after) != (style?.after ?? '');

    /// 返回或关闭弹层前，有改动时先确认放弃。
    Future<void> leave(VoidCallback then) async {
      if (busy.value) {
        return;
      }
      if (dirty() &&
          !await showConfirmDialog(
            context,
            title: context.t(LocaleKeys.commonDiscardChanges),
            confirmLabel: context.t(LocaleKeys.commonDiscard),
            variant: ConfirmDialogVariant.error,
          )) {
        return;
      }
      if (context.mounted) {
        then();
      }
    }

    Future<void> save() async {
      if (!form.validate()) {
        return;
      }
      busy.value = true;
      failed.value = false;
      try {
        final name = value(_StyleField.name).trim();
        if (name.isEmpty) {
          throw const FormatException('Name required');
        }
        await service.save(
          id: style?.id,
          name: name,
          prompt: ProductionStylePrompt(
            before: value(_StyleField.before),
            after: value(_StyleField.after),
          ),
        );
        if (context.mounted) {
          onClose();
        }
      } catch (error, stack) {
        _log.error('style save failed', error: error, stackTrace: stack);
        if (context.mounted) {
          failed.value = true;
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    Widget field(_StyleField f, String label, {bool multiline = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
          child: HookedTextFormField<_StyleField>(
            fieldHook: f,
            label: label,
            multiline: multiline,
          ),
        );
    final colors = RevericTheme.colorsOf(context);
    return HookedForm(
      form: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.md,
              RevericSpacing.md,
              RevericSpacing.md,
              RevericSpacing.xs,
            ),
            child: Row(
              children: [
                RevericIconButton(
                  icon: RevericIcons.arrow_back,
                  tooltip: context.t(LocaleKeys.commonBack),
                  onPressed: () => leave(onClose),
                ),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    context.t(
                      style == null
                          ? LocaleKeys.commonCreate
                          : LocaleKeys.commonEdit,
                    ),
                    style: RevericTheme.typographyOf(context).uiSemibold,
                  ),
                ),
                RevericIconButton(
                  icon: RevericIcons.close,
                  tooltip: context.t(LocaleKeys.commonClose),
                  onPressed: () => leave(onDismiss),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.xl,
                RevericSpacing.md,
                RevericSpacing.xl,
                RevericSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(_StyleField.name, context.t(LocaleKeys.commonName)),
                  field(
                    _StyleField.before,
                    context.t(LocaleKeys.productionStyleBefore),
                    multiline: true,
                  ),
                  field(
                    _StyleField.after,
                    context.t(LocaleKeys.productionStyleAfter),
                    multiline: true,
                  ),
                  if (failed.value)
                    Text(
                      context.t(LocaleKeys.commonSaveFailed),
                      style: RevericTheme.typographyOf(
                        context,
                      ).ui.copyWith(color: colors.error),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.xl,
              vertical: RevericSpacing.md,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                if (style != null)
                  RevericButton.text(
                    label: context.t(LocaleKeys.commonDelete),
                    onPressed: busy.value
                        ? null
                        : () async {
                            final removed = await showConfirmDialog(
                              context,
                              title: context.t(LocaleKeys.commonDelete),
                              message: context.t(
                                LocaleKeys.productionStyleDelete,
                              ),
                              variant: ConfirmDialogVariant.error,
                              onConfirm: () => service.delete(style!.id),
                            );
                            if (removed && context.mounted) {
                              onClose();
                            }
                          },
                  ),
                const Spacer(),
                RevericButton.text(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: busy.value ? null : onClose,
                ),
                const SizedBox(width: RevericSpacing.sm),
                RevericButton.primary(
                  label: context.t(LocaleKeys.commonSave),
                  loading: busy.value,
                  onPressed: busy.value ? null : save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
