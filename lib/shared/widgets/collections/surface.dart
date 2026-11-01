// 职责: 为集合表单和选择器提供桌面弹窗与移动底部弹层外壳。
// 关联文件:
//   lib/mobile/widgets/sheet.dart
//   lib/shared/components/reveric_dialog.dart
import 'package:flutter/material.dart';
import '../../../mobile/widgets/sheet.dart';
import '../../components/reveric_dialog.dart';
import '../../theme/theme.dart';

Future<T?> showCollectionSurface<T>(
  BuildContext context, {
  required bool mobile,
  required WidgetBuilder builder,
}) {
  if (mobile) {
    final theme = RevericTheme.of(context);
    return showMobileSheet<T>(
      context: context,
      builder: (context) => RevericTheme(
        data: theme,
        child: Builder(builder: builder),
      ),
    );
  }
  return showRevericDialog<T>(context: context, builder: builder);
}

class CollectionSurface extends StatelessWidget {
  const CollectionSurface({
    super.key,
    required this.mobile,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final bool mobile;
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return MobileSheetScaffold(
        header: MobileSheetHeader.closable(
          title: title,
          onClose: () => Navigator.of(context).pop(),
        ),
        footer: actions.isEmpty
            ? null
            : Wrap(
                alignment: WrapAlignment.end,
                spacing: RevericSpacing.sm,
                children: actions,
              ),
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          child: child,
        ),
      );
    }
    return RevericDialog.panel(
      title: Text(title),
      content: child,
      actions: actions,
    );
  }
}
