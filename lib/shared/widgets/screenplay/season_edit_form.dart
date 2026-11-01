// 职责: 编辑季名称与规划集数，校验后显式提交。
// 关联文件:
//   lib/shared/widgets/screenplay/season_manager.dart
//   lib/shared/form/form.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../database/novel_content_database.dart' show ScreenplaySeasonRow;
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

enum _SeasonEditField<T> implements FieldSchema {
  title<String>(),
  planned<String>();

  const _SeasonEditField();

  @override
  List<Validator<dynamic>>? get validators => null;
}

class ScreenplaySeasonEditForm extends HookWidget {
  const ScreenplaySeasonEditForm({
    super.key,
    required this.season,
    required this.onCancel,
    required this.onSave,
    required this.busy,
  });

  final ScreenplaySeasonRow season;
  final VoidCallback onCancel;
  final Future<void> Function(String title, int? planned) onSave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final form = useForm<_SeasonEditField>(
      initialValues: {
        _SeasonEditField.title: season.title,
        _SeasonEditField.planned: season.plannedEpisodeCount?.toString() ?? '',
      },
    );

    void submit() {
      if (!form.validate()) {
        return;
      }
      final raw = (form.getValue<String>(_SeasonEditField.planned) ?? '')
          .trim();
      final planned = raw.isEmpty ? null : int.tryParse(raw);
      onSave(form.getValue<String>(_SeasonEditField.title) ?? '', planned);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible + min 高度：表单只有两个字段，撑满弹层会让高度在列表态和
        // 编辑态之间来回跳。键盘顶上来时 Flexible 仍然让滚动区先被压缩，
        // 提交条不会被推出视口。
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x4l),
            child: HookedForm<_SeasonEditField>(
              form: form,
              child: Column(
                children: [
                  HookedTextFormField<_SeasonEditField>(
                    fieldHook: _SeasonEditField.title,
                    label: context.t(LocaleKeys.screenplaySeasonTitle),
                    enabled: !busy,
                  ),
                  const SizedBox(height: RevericSpacing.x4l),
                  HookedTextFormField<_SeasonEditField>(
                    fieldHook: _SeasonEditField.planned,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final raw = (value ?? '').trim();
                      final count = int.tryParse(raw);
                      if (raw.isNotEmpty && (count == null || count < 1)) {
                        return context.t(
                          LocaleKeys.libraryPlannedEpisodeCountInvalid,
                        );
                      }
                      return null;
                    },
                    label: context.t(LocaleKeys.screenplayPlannedEpisodes),
                    enabled: !busy,
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x4l,
            0,
            RevericSpacing.x4l,
            RevericSpacing.x4l,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : onCancel,
                child: Text(context.t(LocaleKeys.commonCancel)),
              ),
              const SizedBox(width: RevericSpacing.sm),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(context.t(LocaleKeys.commonSave)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
