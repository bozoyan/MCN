// 职责: AgentSkill references 左侧文件树 — 展示 SKILL.md 与分层 references，
//   支持目录展开、文件选择，以及编辑态的新增/删除/校验错误标记。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_edit_panel.dart
//   lib/desktop/features/agent_skills/catalog_detail_panel.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_skill_reference.dart';
import '../../../shared/theme/theme.dart';

/// AgentSkill 左侧文件树：SKILL.md 主体 + 可折叠 references 目录。
class AgentSkillReferenceFileTree extends StatefulWidget {
  const AgentSkillReferenceFileTree({
    super.key,
    required this.references,
    required this.selectedIndex,
    required this.onSelectMain,
    required this.onSelectReference,
    this.invalidIndices = const {},
    this.readOnly = false,
    this.onAddReference,
    this.onDeleteReference,
  });

  final List<AgentSkillReferenceFile> references;

  /// -1 = 主体；>=0 = references 下标。
  final int selectedIndex;

  /// 校验不通过的 reference 下标，行尾显示警告标记。
  final Set<int> invalidIndices;
  final bool readOnly;
  final VoidCallback onSelectMain;
  final ValueChanged<int> onSelectReference;
  final ValueChanged<String>? onAddReference;
  final ValueChanged<int>? onDeleteReference;

  @override
  State<AgentSkillReferenceFileTree> createState() =>
      _AgentSkillReferenceFileTreeState();
}

class _AgentSkillReferenceFileTreeState
    extends State<AgentSkillReferenceFileTree> {
  /// 仅记录用户收起的目录，使后续新建或改名产生的目录默认展开。
  Set<String> _collapsedDirectories = const {};

  bool _isExpanded(String directoryPath) {
    return !_collapsedDirectories.contains(directoryPath);
  }

  void _toggleDirectory(String directoryPath) {
    setState(() {
      final next = Set<String>.from(_collapsedDirectories);
      if (!next.add(directoryPath)) {
        next.remove(directoryPath);
      }
      _collapsedDirectories = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final referenceTree = _ReferenceTreeDirectory.fromReferences(
      widget.references,
    );
    final canAdd =
        !widget.readOnly &&
        widget.onAddReference != null &&
        widget.references.length < AgentSkillReferences.maxCount;

    return SizedBox(
      width: 220,
      child: Container(
        color: colors.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.x2l,
                RevericSpacing.x2l,
                RevericSpacing.sm,
              ),
              child: Text(
                context.t(LocaleKeys.agentSkillFiles),
                style: typo.uiSemibold.copyWith(color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                ),
                children: [
                  _SkillFileRow(
                    icon: RevericIcons.layers_outlined,
                    label: context.t(LocaleKeys.agentSkillMainDocument),
                    selected: widget.selectedIndex == -1,
                    onTap: widget.onSelectMain,
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  _ReferenceFolderRow(
                    label: AgentSkillReferences.relativeDir,
                    depth: 0,
                    isExpanded: _isExpanded(referenceTree.path),
                    onTap: () => _toggleDirectory(referenceTree.path),
                  ),
                  if (_isExpanded(referenceTree.path)) ...[
                    const SizedBox(height: RevericSpacing.xxs),
                    ..._buildReferenceTreeRows(
                      referenceTree,
                      depth: 1,
                      canAdd: canAdd,
                    ),
                    if (canAdd)
                      _AddReferenceRow(
                        depth: 1,
                        onTap: () => widget.onAddReference!(referenceTree.path),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildReferenceTreeRows(
    _ReferenceTreeDirectory directory, {
    required int depth,
    required bool canAdd,
  }) {
    final rows = <Widget>[];
    for (final childDirectory in directory.directories.values) {
      rows.add(
        _ReferenceFolderRow(
          label: childDirectory.name,
          depth: depth,
          isExpanded: _isExpanded(childDirectory.path),
          onTap: () => _toggleDirectory(childDirectory.path),
        ),
      );
      rows.add(const SizedBox(height: RevericSpacing.xxs));
      if (_isExpanded(childDirectory.path)) {
        rows.addAll(
          _buildReferenceTreeRows(
            childDirectory,
            depth: depth + 1,
            canAdd: canAdd,
          ),
        );
        if (canAdd) {
          rows.add(
            _AddReferenceRow(
              depth: depth + 1,
              onTap: () => widget.onAddReference!(childDirectory.path),
            ),
          );
          rows.add(const SizedBox(height: RevericSpacing.xxs));
        }
      }
    }
    for (final file in directory.files) {
      rows.add(
        _SkillFileRow(
          icon: RevericIcons.description_outlined,
          label: file.label,
          selected: widget.selectedIndex == file.index,
          hasError: widget.invalidIndices.contains(file.index),
          indent: depth * RevericSpacing.lg,
          onTap: () => widget.onSelectReference(file.index),
          onDelete: widget.readOnly || widget.onDeleteReference == null
              ? null
              : () => widget.onDeleteReference!(file.index),
        ),
      );
      rows.add(const SizedBox(height: RevericSpacing.xxs));
    }
    return rows;
  }
}

/// references 目录节点。保留传入顺序，避免 UI 树改变编辑中的文件顺序。
class _ReferenceTreeDirectory {
  _ReferenceTreeDirectory({required this.name, required this.path});

  final String name;
  final String path;
  final Map<String, _ReferenceTreeDirectory> directories = {};
  final List<_ReferenceTreeFile> files = [];

  factory _ReferenceTreeDirectory.fromReferences(
    List<AgentSkillReferenceFile> references,
  ) {
    final root = _ReferenceTreeDirectory(
      name: AgentSkillReferences.relativeDir,
      path: AgentSkillReferences.relativeDir,
    );
    for (var index = 0; index < references.length; index++) {
      final path = references[index].path;
      final relativePath =
          path.startsWith(AgentSkillReferences.relativeDirPrefix)
          ? path.substring(AgentSkillReferences.relativeDirPrefix.length)
          : path;
      final segments = relativePath.split('/');
      // 编辑期间允许暂存非法路径；此类文件保留原路径显示，交由现有校验提示。
      if (segments.length == 1 || segments.any((segment) => segment.isEmpty)) {
        root.files.add(_ReferenceTreeFile(index: index, label: relativePath));
        continue;
      }

      var directory = root;
      for (final segment in segments.take(segments.length - 1)) {
        directory = directory.directories.putIfAbsent(
          segment,
          () => _ReferenceTreeDirectory(
            name: segment,
            path: '${directory.path}/$segment',
          ),
        );
      }
      directory.files.add(
        _ReferenceTreeFile(index: index, label: segments.last),
      );
    }
    return root;
  }
}

class _ReferenceTreeFile {
  const _ReferenceTreeFile({required this.index, required this.label});

  final int index;
  final String label;
}

class _ReferenceFolderRow extends StatelessWidget {
  const _ReferenceFolderRow({
    required this.label,
    required this.depth,
    required this.isExpanded,
    required this.onTap,
  });

  final String label;
  final int depth;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            RevericSpacing.md + depth * RevericSpacing.lg,
            RevericSpacing.sm,
            RevericSpacing.md,
            RevericSpacing.sm,
          ),
          child: Row(
            children: [
              RevericIcon(
                isExpanded
                    ? RevericIcons.expand_more
                    : RevericIcons.caret_right,
                size: 14,
                color: colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.xs),
              RevericIcon(
                RevericIcons.folder_outlined,
                size: 15,
                color: colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.textSubtle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddReferenceRow extends StatelessWidget {
  const _AddReferenceRow({required this.depth, required this.onTap});

  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            RevericSpacing.md + depth * RevericSpacing.lg,
            RevericSpacing.sm,
            RevericSpacing.md,
            RevericSpacing.sm,
          ),
          child: Row(
            children: [
              RevericIcon(
                RevericIcons.add,
                size: 15,
                color: colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.agentSkillReferencesAdd),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillFileRow extends StatelessWidget {
  const _SkillFileRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.hasError = false,
    this.indent = 0,
    this.onDelete,
  });

  final String icon;
  final String label;
  final bool selected;
  final bool hasError;
  final double indent;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final foreground = hasError
        ? colors.warningText
        : (selected ? colors.accent : colors.textSecondary);
    return Material(
      color: selected
          ? colors.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            RevericSpacing.md + indent,
            RevericSpacing.sm,
            RevericSpacing.md,
            RevericSpacing.sm,
          ),
          child: Row(
            children: [
              RevericIcon(icon, size: 15, color: foreground),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected ? typo.uiSmallSemibold : typo.uiSmall)
                      .copyWith(color: foreground),
                ),
              ),
              if (hasError) ...[
                const SizedBox(width: RevericSpacing.xs),
                RevericIcon(
                  RevericIcons.warning_circle,
                  size: 13,
                  color: colors.warningText,
                ),
              ],
              if (onDelete != null) ...[
                const SizedBox(width: RevericSpacing.xs),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: RevericIcon(
                      RevericIcons.delete_outline,
                      size: 14,
                      color: colors.textSubtle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
