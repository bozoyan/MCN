// 职责: AgentSkill 导出对话框 — 勾选要导出的已安装技能条目，并选择文件夹或 ZIP 格式。
// 关联文件:
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';

import '../components/reveric_button.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/novel_agent_skill.dart';
import '../theme/theme.dart';

/// 导出目标格式。
enum AgentSkillExportMode {
  /// 每个技能一个目录（含 SKILL.md），写入所选文件夹。
  folder,

  /// 全部打成单个 .zip（内含多个 skill 目录）。
  zip,
}

/// 用户确认导出后的请求：已选条目 + 格式。
class AgentSkillExportRequest {
  const AgentSkillExportRequest({required this.entries, required this.mode});

  final List<NovelAgentSkillModel> entries;
  final AgentSkillExportMode mode;
}

/// 弹出导出对话框。取消或关闭返回 `null`。
Future<AgentSkillExportRequest?> showAgentSkillExportDialog(
  BuildContext context, {
  required List<NovelAgentSkillModel> entries,
}) {
  assert(entries.isNotEmpty, 'entries must not be empty');
  final theme = RevericTheme.of(context);
  return showDialog<AgentSkillExportRequest>(
    context: context,
    builder: (dialogContext) {
      return RevericTheme(
        data: theme,
        child: _AgentSkillExportDialog(entries: entries),
      );
    },
  );
}

class _AgentSkillExportDialog extends StatefulWidget {
  const _AgentSkillExportDialog({required this.entries});

  final List<NovelAgentSkillModel> entries;

  @override
  State<_AgentSkillExportDialog> createState() =>
      _AgentSkillExportDialogState();
}

class _AgentSkillExportDialogState extends State<_AgentSkillExportDialog> {
  late Set<String> _selectedIds;
  AgentSkillExportMode _mode = AgentSkillExportMode.zip;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.entries.map((e) => e.id).toSet();
  }

  bool get _allSelected => _selectedIds.length == widget.entries.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds = <String>{};
      } else {
        _selectedIds = widget.entries.map((e) => e.id).toSet();
      }
    });
  }

  void _toggle(String id) {
    setState(() {
      final next = Set<String>.from(_selectedIds);
      if (!next.remove(id)) {
        next.add(id);
      }
      _selectedIds = next;
    });
  }

  void _confirm() {
    final selected = widget.entries
        .where((e) => _selectedIds.contains(e.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(AgentSkillExportRequest(entries: selected, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final selectedCount = _selectedIds.length;
    final canExport = selectedCount > 0;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: context.t(LocaleKeys.agentSkillExport),
              subtitle: context.t(LocaleKeys.agentSkillExportSubtitle),
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Divider(
              height: RevericSizes.dividerThickness,
              color: colors.borderSubtle,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x3l,
                RevericSpacing.x3l,
                RevericSpacing.x3l,
                RevericSpacing.x2l,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.t(LocaleKeys.agentSkillExportFormat),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _FormatCard(
                          selected: _mode == AgentSkillExportMode.folder,
                          icon: RevericIcons.folder_outlined,
                          title: context.t(LocaleKeys.agentSkillExportFolder),
                          hint: context.t(
                            LocaleKeys.agentSkillExportFolderHint,
                          ),
                          onTap: () => setState(
                            () => _mode = AgentSkillExportMode.folder,
                          ),
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      Expanded(
                        child: _FormatCard(
                          selected: _mode == AgentSkillExportMode.zip,
                          icon: RevericIcons.archive_outlined,
                          title: context.t(LocaleKeys.agentSkillExportZip),
                          hint: context.t(LocaleKeys.agentSkillExportZipHint),
                          onTap: () =>
                              setState(() => _mode = AgentSkillExportMode.zip),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.x3l),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t(LocaleKeys.agentSkillExportSelectSkills),
                          style: typo.uiSmallSemibold.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        context.t(
                          LocaleKeys.agentSkillExportSelectedCount,
                          namedArgs: {
                            'selected': '$selectedCount',
                            'total': '${widget.entries.length}',
                          },
                        ),
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      RevericButton.text(
                        size: RevericButtonSize.compact,
                        label: context.t(
                          _allSelected
                              ? LocaleKeys.agentSkillExportDeselectAll
                              : LocaleKeys.agentSkillExportSelectAll,
                        ),
                        onPressed: _toggleAll,
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 120,
                        maxHeight: 280,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: RevericSpacing.xs,
                        ),
                        itemCount: widget.entries.length,
                        separatorBuilder: (_, _) => Divider(
                          height: RevericSizes.dividerThickness,
                          indent: RevericSpacing.x3l + 22,
                          color: colors.borderSubtle,
                        ),
                        itemBuilder: (context, index) {
                          final entry = widget.entries[index];
                          final selected = _selectedIds.contains(entry.id);
                          return _SkillRow(
                            name: entry.name,
                            category: entry.category,
                            selected: selected,
                            onTap: () => _toggle(entry.id),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: RevericSizes.dividerThickness,
              color: colors.borderSubtle,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x3l,
                RevericSpacing.lg,
                RevericSpacing.x3l,
                RevericSpacing.x3l,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(context.t(LocaleKeys.commonCancel)),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  FilledButton(
                    onPressed: canExport ? _confirm : null,
                    child: Text(
                      context.t(
                        LocaleKeys.agentSkillExportConfirm,
                        namedArgs: {'count': '$selectedCount'},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x3l,
        RevericSpacing.x3l,
        RevericSpacing.x3l,
        RevericSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: RevericIcon(
              RevericIcons.download,
              size: 18,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: RevericIcon(
              RevericIcons.close,
              size: 16,
              color: colors.textMuted,
            ),
            iconSize: RevericSizes.iconButtonSize,
            constraints: const BoxConstraints(
              minWidth: RevericSizes.iconButtonSize,
              minHeight: RevericSizes.iconButtonSize,
            ),
            padding: EdgeInsets.zero,
            splashRadius: RevericSizes.iconButtonSize / 2,
          ),
        ],
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final bool selected;
  final String icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: selected
          ? colors.accent.withValues(alpha: 0.08)
          : colors.surfaceContainer,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Container(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RevericIcon(
                icon,
                size: 20,
                color: selected ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(height: RevericSpacing.sm),
              Text(
                title,
                style: typo.uiSmallSemibold.copyWith(
                  color: selected ? colors.accent : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(hint, style: typo.uiTiny.copyWith(color: colors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.name,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.md,
        ),
        child: Row(
          children: [
            _CheckBox(selected: selected),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ),
            if (category.isNotEmpty) ...[
              const SizedBox(width: RevericSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  category,
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? colors.accent : Colors.transparent,
        border: Border.all(
          color: selected ? colors.accent : colors.borderInput,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: selected
          ? RevericIcon(RevericIcons.check, size: 12, color: colors.onAccent)
          : null,
    );
  }
}
