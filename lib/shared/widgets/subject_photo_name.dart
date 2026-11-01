// 职责: 显示照片名称并提交重命名，在保存失败时保留输入供重试。
// 关联文件:
//   lib/shared/models/subject_photo.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/mobile/widgets/sheet.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../mobile/widgets/sheet.dart';
import '../components/reveric_button.dart';
import '../components/reveric_dialog.dart';
import '../components/reveric_text_field.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../models/subject_photo.dart';
import '../theme/theme.dart';

final _log = AppLogger.forModule('Photo');

class SubjectPhotoName extends StatelessWidget {
  const SubjectPhotoName({
    super.key,
    required this.photo,
    required this.onRename,
  });

  final SubjectPhoto photo;
  final Future<void> Function(String name) onRename;

  @override
  Widget build(BuildContext context) {
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    return Tooltip(
      message: context.t(LocaleKeys.commonRename),
      child: RevericButton.text(
        label: photo.name.isEmpty
            ? context.t(LocaleKeys.commonUntitled)
            : photo.name,
        labelMaxLines: 1,
        size: mobile ? RevericButtonSize.standard : RevericButtonSize.compact,
        onPressed: () {
          Widget form(BuildContext context) =>
              _NameForm(name: photo.name, onSave: onRename, mobile: mobile);
          if (mobile) {
            final theme = RevericTheme.of(context);
            showMobileSheet<void>(
              context: context,
              isDismissible: false,
              enableDrag: false,
              builder: (_) => RevericTheme(
                data: theme,
                child: Builder(builder: form),
              ),
            );
          } else {
            showRevericDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: form,
            );
          }
        },
      ),
    );
  }
}

class _NameForm extends HookWidget {
  const _NameForm({
    required this.name,
    required this.onSave,
    required this.mobile,
  });
  final String name;
  final Future<void> Function(String name) onSave;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: name);
    final busy = useState(false);
    final error = useState<String?>(null);
    Future<void> save() async {
      if (busy.value ||
          controller.value.composing.isValid &&
              !controller.value.composing.isCollapsed) {
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await onSave(controller.text.trim());
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (failure, stackTrace) {
        _log.error('Rename failed', error: failure, stackTrace: stackTrace);
        if (context.mounted) {
          error.value = context.t(LocaleKeys.commonSaveFailed);
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    final title = context.t(LocaleKeys.commonRename);
    final input = SingleChildScrollView(
      child: RevericTextField(
        controller: controller,
        label: context.t(LocaleKeys.commonName),
        autofocus: true,
        enabled: !busy.value,
        errorText: error.value,
        onSubmitted: (_) => save(),
      ),
    );
    final actions = [
      RevericButton.text(
        label: context.t(LocaleKeys.commonCancel),
        onPressed: busy.value ? null : () => Navigator.of(context).pop(),
      ),
      RevericButton.primary(
        label: context.t(LocaleKeys.commonSave),
        loading: busy.value,
        onPressed: save,
      ),
    ];
    return PopScope(
      canPop: !busy.value,
      child: mobile
          ? MobileSheetScaffold(
              header: Padding(
                padding: const EdgeInsets.all(RevericSpacing.lg),
                child: Text(
                  title,
                  style: RevericTheme.typographyOf(context).uiSemibold,
                ),
              ),
              footer: Wrap(
                alignment: WrapAlignment.end,
                spacing: RevericSpacing.sm,
                children: actions,
              ),
              child: Padding(
                padding: const EdgeInsets.all(RevericSpacing.lg),
                child: input,
              ),
            )
          : RevericDialog.panel(
              title: Text(title),
              content: input,
              actions: actions,
            ),
    );
  }
}
