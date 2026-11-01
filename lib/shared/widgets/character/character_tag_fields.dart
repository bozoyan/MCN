// 职责: 人物「别名与称号」「分组」两个标签字段 — 标题 + 标签编辑器 + 校验提示，桌面与移动端共用。
// 关联文件:
//   lib/shared/components/reveric_tags_editor.dart
//   lib/shared/models/character_profile.dart
//   lib/desktop/widgets/workspace/character_profile_editor.dart
//   lib/mobile/pages/character_editor_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_tags_editor.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/character_profile.dart';
import '../../theme/theme.dart';

/// 别名与称号：与主名重复的别名被拒绝并就地提示。
class CharacterAliasesField extends HookWidget {
  const CharacterAliasesField({
    super.key,
    required this.characterName,
    required this.aliases,
    required this.onChanged,
  });

  final String characterName;
  final List<String> aliases;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final errorText = useState<String?>(null);

    void handleChanged(List<String> next) {
      final name = characterName.trim().toLowerCase();
      final added = next.where((alias) => !aliases.contains(alias));
      if (name.isNotEmpty &&
          added.any((alias) => alias.trim().toLowerCase() == name)) {
        errorText.value = context.t(LocaleKeys.workspaceCharacterAliasInvalid);
        return;
      }
      errorText.value = null;
      onChanged(next);
    }

    return _CharacterTagField(
      label: context.t(LocaleKeys.workspaceCharacterAliasesLabel),
      errorText: errorText.value,
      child: RevericTagsEditor(
        tags: aliases,
        onChanged: handleChanged,
        addLabel: context.t(LocaleKeys.workspaceCharacterAliasesAdd),
        hintText: context.t(LocaleKeys.workspaceCharacterAliasesHint),
        maxLength: characterTagMaxLength,
      ),
    );
  }
}

/// 分组：按宗门、家族、阵营等维度归类人物，供列表检索使用。
class CharacterGroupsField extends StatelessWidget {
  const CharacterGroupsField({
    super.key,
    required this.groups,
    required this.onChanged,
  });

  final List<String> groups;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return _CharacterTagField(
      label: context.t(LocaleKeys.workspaceCharacterTagsLabel),
      child: RevericTagsEditor(
        tags: groups,
        onChanged: onChanged,
        addLabel: context.t(LocaleKeys.workspaceCharacterTagsAdd),
        hintText: context.t(LocaleKeys.workspaceCharacterTagsHint),
        maxLength: characterTagMaxLength,
      ),
    );
  }
}

class _CharacterTagField extends StatelessWidget {
  const _CharacterTagField({
    required this.label,
    required this.child,
    this.errorText,
  });

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      // 标签框跟同分组的输入框一样占满可用宽度，否则 Wrap 会缩到内容宽度。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: typo.uiSemibold.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: RevericSpacing.sm),
        child,
        if (errorText != null) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(errorText!, style: typo.uiSmall.copyWith(color: colors.error)),
        ],
      ],
    );
  }
}
