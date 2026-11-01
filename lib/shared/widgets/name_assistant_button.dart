// 职责: 起名助手按钮 — 嵌入 name/title 输入框的 suffixIcon，支持随机和 AI 起名
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/services/name_generator_service.dart
//   lib/shared/services/ai/chat.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/name_assistant.json
//   assets/translations/zh-CN/name_assistant.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../services/name_generator_service.dart';
import '../services/ai/chat.dart';
import '../theme/theme.dart';
import '../localization/locale_keys.dart';
import '../localization/app_localization.dart';
import '../components/reveric_dialog.dart';
import '../components/reveric_button.dart';

class NameAssistantButton extends StatelessWidget {
  const NameAssistantButton({
    super.key,
    required this.nameType,
    required this.onNameGenerated,
    this.aiClient,
    this.novelContext,
    this.novel,
    this.entityDescription,
  });

  final NameType nameType;
  final ValueChanged<String> onNameGenerated;
  final AiClient? aiClient;
  final String? novelContext;
  final Novel? novel;
  final String? entityDescription;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return IconButton(
      icon: RevericIcon(
        RevericIcons.auto_awesome_outlined,
        size: 16,
        color: colors.textSubtle,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: context.t(LocaleKeys.commonNameAssistant),
      onPressed: () => _showPickerDialog(context),
    );
  }

  void _showPickerDialog(BuildContext context) {
    showRevericDialog<void>(
      context: context,
      builder: (ctx) => _NamePickerDialog(
        nameType: nameType,
        aiClient: aiClient,
        novelContext: novelContext,
        novel: novel,
        entityDescription: entityDescription,
        onNameGenerated: onNameGenerated,
      ),
    );
  }
}

class _NamePickerDialog extends StatefulWidget {
  const _NamePickerDialog({
    required this.nameType,
    required this.onNameGenerated,
    this.aiClient,
    this.novelContext,
    this.novel,
    this.entityDescription,
  });

  final NameType nameType;
  final ValueChanged<String> onNameGenerated;
  final AiClient? aiClient;
  final String? novelContext;
  final Novel? novel;
  final String? entityDescription;

  @override
  State<_NamePickerDialog> createState() => _NamePickerDialogState();
}

class _NamePickerDialogState extends State<_NamePickerDialog> {
  var _isGenerating = false;
  String? _error;
  String? _selectedName;
  var _generatedNames = <String>[];

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final typeLabel = switch (widget.nameType) {
      NameType.character => context.t(LocaleKeys.entityTypeCharacter),
      NameType.skill => context.t(LocaleKeys.entityTypeSkill),
      NameType.item => context.t(LocaleKeys.entityTypeItem),
      NameType.creature => context.t(LocaleKeys.entityTypeCreature),
      NameType.location => context.t(LocaleKeys.entityTypeLocation),
    };

    return RevericDialog.panel(
      title: Text(
        context.t(
          LocaleKeys.nameAssistantTitle,
          namedArgs: {'type': typeLabel},
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_generatedNames.isNotEmpty) ...[
              _NameCandidates(
                names: _generatedNames,
                selectedName: _selectedName,
                onSelected: (name) {
                  setState(() {
                    _selectedName = name;
                  });
                },
              ),
              const SizedBox(height: RevericSpacing.lg),
            ],
            if (_isGenerating) ...[
              const Padding(
                padding: EdgeInsets.all(RevericSpacing.x4l),
                child: CircularProgressIndicator(),
              ),
              const SizedBox(height: RevericSpacing.md),
              Text(
                context.t(LocaleKeys.nameAssistantGenerating),
                style: typo.body.copyWith(color: colors.textSecondary),
              ),
            ] else ...[
              _ActionButton(
                icon: RevericIcons.shuffle_outlined,
                label: context.t(LocaleKeys.nameAssistantRandom),
                onTap: _handleRandom,
              ),
              if (widget.aiClient != null) ...[
                const SizedBox(height: RevericSpacing.md),
                _ActionButton(
                  icon: RevericIcons.auto_awesome_outlined,
                  label: context.t(LocaleKeys.nameAssistantAI),
                  onTap: _handleAI,
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: RevericSpacing.md),
              Text(
                _error!,
                style: typo.bodySmall.copyWith(color: colors.warningText),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),

      width: 360 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: _selectedName != null
              ? context.t(LocaleKeys.nameAssistantUseName)
              : context.t(LocaleKeys.commonCancel),
          onPressed: () {
            if (_selectedName != null) {
              widget.onNameGenerated(_selectedName!);
            }
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _handleRandom() {
    setState(() {
      _error = null;
      final names = NameGeneratorService.randomNames(
        widget.nameType,
        count: NameGeneratorService.aiNameBatchSize,
      );
      _generatedNames = names;
      _selectedName = names.first;
    });
  }

  Future<void> _handleAI() async {
    setState(() {
      _isGenerating = true;
      _error = null;
      _selectedName = null;
      _generatedNames = [];
    });

    try {
      final names = await NameGeneratorService.generateAINames(
        type: widget.nameType,
        aiClient: widget.aiClient!,
        count: NameGeneratorService.aiNameBatchSize,
        context: widget.novelContext,
        novel: widget.novel,
        entityDescription: widget.entityDescription,
      );
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generatedNames = names;
        _selectedName = names.isNotEmpty ? names.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _error = context.t(LocaleKeys.nameAssistantAIError);
        _generatedNames = [];
        _selectedName = null;
      });
    }
  }
}

class _NameCandidates extends StatelessWidget {
  const _NameCandidates({
    required this.names,
    required this.selectedName,
    required this.onSelected,
  });

  final List<String> names;
  final String? selectedName;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: RevericSpacing.sm,
          runSpacing: RevericSpacing.sm,
          children: [
            for (final name in names)
              _NameCandidateChip(
                name: name,
                selected: name == selectedName,
                colors: colors,
                typo: typo,
                onTap: () => onSelected(name),
              ),
          ],
        ),
      ),
    );
  }
}

class _NameCandidateChip extends StatelessWidget {
  const _NameCandidateChip({
    required this.name,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? colors.accent : colors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 96),
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.08)
                : colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          child: Text(
            name,
            style: typo.uiSemibold.copyWith(color: textColor),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: RevericIcon(icon, size: 18, color: colors.accent),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accent,
          side: BorderSide(color: colors.accent.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
          textStyle: typo.ui.copyWith(color: colors.accent),
        ),
      ),
    );
  }
}
