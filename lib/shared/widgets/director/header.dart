// 职责: 导演台顶栏 — 展示保存状态、提供关闭入口，居中承载视角下拉与画幅，右侧放宿主操作；项目名称由宿主的面包屑显示。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/workspace.dart
//   lib/shared/widgets/director/aspect.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'package:flutter/material.dart';
import '../../components/reveric_icon_button.dart';
import '../../services/director/session.dart';
import '../../theme/theme.dart';
import 'aspect.dart';
import 'strings.dart';

class DirectorHeader extends StatelessWidget {
  const DirectorHeader({
    super.key,
    required this.session,
    required this.onBack,
    this.center,
    this.trailing,
  });
  final DirectorSession session;
  final VoidCallback onBack;

  /// 顶栏居中的控件（工作区传入视角下拉）。
  final Widget? center;

  /// 顶栏右侧的宿主操作（导出）；[compact] 时只放图标。
  final Widget Function(bool compact)? trailing;

  /// 低于这个宽度时画幅和右侧操作只显示图标，给视角下拉和保存状态让位。
  static const double _compactWidth = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _build(context, compact: constraints.maxWidth < _compactWidth),
    );
  }

  Widget _build(BuildContext context, {required bool compact}) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      constraints: const BoxConstraints(
        minHeight: RevericSizes.directorHeaderHeight,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.sm,
          vertical: RevericSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  RevericIconButton(
                    icon: RevericIcons.close,
                    tooltip: tr(context, 'back'),
                    onPressed: onBack,
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  Flexible(
                    child: Text(
                      tr(
                        context,
                        session.history.dirty || session.hasPendingInput
                            ? 'unsaved'
                            : 'saved',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            ?center,
            const SizedBox(width: RevericSpacing.sm),
            DirectorAspectButton(session: session, compact: compact),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing?.call(compact),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
