// 职责: 折叠侧边栏 — 提供紧凑导航、返回入口与展开操作。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/desktop/widgets/desktop_window_frame.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/theme/theme.dart';
import '../desktop_window_frame.dart';

class CollapsedSidebar extends StatelessWidget {
  const CollapsedSidebar({
    super.key,
    required this.selection,
    required this.onSelect,
    required this.onExpand,
    required this.onEditDetails,
    required this.onCreateChapter,
    required this.onBack,
  });

  static const double width = 48;

  /// Extra left padding the content panel needs to clear macOS traffic lights.
  static double get contentLeadingInset {
    if (!Platform.isMacOS) return 0.0;
    final trafficLightOverflow =
        DesktopWindowFrame.macosTrafficLightWidth -
        width -
        RevericSizes.dividerThickness;
    final titleBarButtonClearance =
        DesktopWindowFrame.sidebarLeadingInset +
        RevericSpacing.sm +
        28 +
        RevericSpacing.md -
        width -
        RevericSizes.dividerThickness -
        RevericSpacing.x2l;
    return math.max(
      0.0,
      math.max(trafficLightOverflow, titleBarButtonClearance),
    );
  }

  final WorkspaceSelection selection;
  final ValueSetter<WorkspaceSelection> onSelect;
  final VoidCallback onExpand;
  final VoidCallback onEditDetails;
  final Future<void> Function() onCreateChapter;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(height: DesktopWindowFrame.sidebarTopInset),
          const SizedBox(height: RevericSpacing.sm),
          Tooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: _buildIconButton(
              context,
              icon: RevericIcons.chevron_left,
              onTap: onBack,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: RevericSpacing.xs),
          _buildNavButton(
            context,
            icon: RevericIcons.space_dashboard_outlined,
            label: context.t(LocaleKeys.workspaceOverview),
            selected: selection.section == NovelWorkspaceSection.overview,
            onTap: () => onSelect(const WorkspaceSelection.overview()),
          ),
          const SizedBox(height: RevericSpacing.sm),
          _buildIconButton(
            context,
            icon: RevericIcons.edit_outlined,
            onTap: onEditDetails,
          ),
          _buildIconButton(
            context,
            icon: RevericIcons.add,
            onTap: onCreateChapter,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required String icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final colors = RevericTheme.colorsOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.small),
      hoverColor: colors.hover,
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.xs),
          child: Center(
            child: RevericIcon(
              icon,
              size: 18,
              color: color ?? colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(
    BuildContext context, {
    required String icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = RevericTheme.colorsOf(context);

    return Tooltip(
      message: label,
      child: Container(
        color: selected ? colors.selected : Colors.transparent,
        child: _buildIconButton(
          context,
          icon: icon,
          onTap: onTap,
          color: selected ? colors.accent : colors.textMuted,
        ),
      ),
    );
  }
}
