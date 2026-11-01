// 职责: 桌面角色选择浮层 — 在角色行旁稳定展示选择内容，并交出选中/切换动作两个出口。
// 关联文件:
//   lib/shared/widgets/screenplay/character_picker.dart
//   lib/desktop/features/screenplay/script.dart
//   lib/shared/components/reveric_context_menu.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/character_picker.dart';

/// 浮层出口：选中人物、或把这一行退回动作元素。
class ScreenplayCharacterPickerResult {
  const ScreenplayCharacterPickerResult.character(String this.characterId)
    : switchToAction = false;

  const ScreenplayCharacterPickerResult.switchToAction()
    : characterId = null,
      switchToAction = true;

  final String? characterId;
  final bool switchToAction;
}

const double _popoverWidth = 280;
const double _popoverMaxHeight = 320;

/// 在 [anchor]（全局坐标下的角色行矩形）旁弹出角色选择浮层，下方不足时置于上方。
///
/// [allowSwitchToAction] 暂时默认关闭，同时隐藏提示并停用 Tab 切换。
/// 返回 null 表示取消（Esc 或点空白），元素不应发生任何变化。
Future<ScreenplayCharacterPickerResult?> showScreenplayCharacterPickerPopover(
  BuildContext context, {
  required Rect anchor,
  required String databasePath,
  String? selectedId,
  List<String> priorityIds = const [],
  bool allowSwitchToAction = false,
}) {
  final colors = RevericTheme.colorsOf(context);
  return Navigator.of(context, rootNavigator: true).push(
    _CharacterPickerRoute(
      anchor: anchor,
      databasePath: databasePath,
      selectedId: selectedId,
      priorityIds: priorityIds,
      allowSwitchToAction: allowSwitchToAction,
      colors: colors,
    ),
  );
}

class _CharacterPickerRoute
    extends PopupRoute<ScreenplayCharacterPickerResult> {
  _CharacterPickerRoute({
    required this.anchor,
    required this.databasePath,
    required this.selectedId,
    required this.priorityIds,
    required this.allowSwitchToAction,
    required this.colors,
  });

  final Rect anchor;
  final String databasePath;
  final String? selectedId;
  final List<String> priorityIds;
  final bool allowSwitchToAction;
  final RevericColors colors;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    void close(ScreenplayCharacterPickerResult? result) {
      if (isCurrent) {
        Navigator.of(context).pop(result);
      }
    }

    return CustomSingleChildLayout(
      delegate: _AnchoredLayout(
        anchor: anchor,
        padding: MediaQuery.paddingOf(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: _popoverWidth,
          // 搜索结果只改变列表内容，不能改变弹层高度，否则上下定位会随输入翻转。
          // 小窗口仍由 _AnchoredLayout 的视口约束压缩高度。
          height: _popoverMaxHeight,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.textPrimary.withValues(alpha: 0.16),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ScreenplayCharacterPickerBody(
            databasePath: databasePath,
            selectedId: selectedId,
            priorityIds: priorityIds,
            showShortcutHints: true,
            onPick: (id) =>
                close(ScreenplayCharacterPickerResult.character(id)),
            onSwitchToAction: allowSwitchToAction
                ? () => close(
                    const ScreenplayCharacterPickerResult.switchToAction(),
                  )
                : null,
            onCancel: () => close(null),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

/// 贴在角色行左下角；下方放不下就翻到行上方，再夹进视口。
class _AnchoredLayout extends SingleChildLayoutDelegate {
  _AnchoredLayout({required this.anchor, required this.padding});

  final Rect anchor;
  final EdgeInsets padding;

  static const double _margin = 8;
  static const double _gap = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(
      const EdgeInsets.symmetric(horizontal: _margin, vertical: _margin) +
          padding,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minY = padding.top + _margin;
    final maxY = size.height - padding.bottom - _margin - childSize.height;
    var y = anchor.bottom + _gap;
    if (y > maxY) {
      final above = anchor.top - _gap - childSize.height;
      y = above >= minY ? above : maxY;
    }
    final minX = padding.left + _margin;
    final maxX = size.width - padding.right - _margin - childSize.width;
    final x = anchor.left.clamp(minX, maxX < minX ? minX : maxX);
    return Offset(x, y.clamp(minY, maxY < minY ? minY : maxY));
  }

  @override
  bool shouldRelayout(_AnchoredLayout oldDelegate) {
    return anchor != oldDelegate.anchor || padding != oldDelegate.padding;
  }
}
