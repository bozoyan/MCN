// 职责: 为移动剧本提供顶部元素插入工具条，命令由当前编辑场次提供。
// 关联文件:
//   lib/mobile/features/screenplay/scene_editor.dart
//   lib/shared/widgets/screenplay/element_options.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import '../../../shared/components/horizontal_wheel_scroll.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/models/screenplay_element.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/element_options.dart';

class MobileScreenplayElementCommands extends ChangeNotifier {
  String? sceneId;
  ScreenplayElementType? selectedType;
  VoidCallback? editScene;
  Future<void> Function(ScreenplayElementType)? insert;
  bool Function(ScreenplayElementType)? canInsert;

  void refresh() => notifyListeners();
}

class MobileScreenplayElementBar extends StatelessWidget {
  const MobileScreenplayElementBar({super.key, required this.commands});
  final MobileScreenplayElementCommands commands;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      padding: const EdgeInsets.all(RevericSpacing.xs),
      child: ListenableBuilder(
        listenable: commands,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: HorizontalWheelScroll(
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final option in screenplayElementOptions)
                        SizedBox(
                          width: RevericSpacing.x6l,
                          child: Tooltip(
                            message: context.t(option.labelKey),
                            child: InkWell(
                              onTap: option.type == null
                                  ? commands.editScene
                                  : commands.insert != null &&
                                        (commands.canInsert?.call(
                                              option.type!,
                                            ) ??
                                            false)
                                  ? () => commands.insert!(option.type!)
                                  : null,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RevericIcon(
                                      option.icon,
                                      size: 18,
                                      color:
                                          option.type != null &&
                                              commands.selectedType ==
                                                  option.type
                                          ? colors.accent
                                          : colors.textMuted,
                                    ),
                                    const SizedBox(height: RevericSpacing.xs),
                                    Text(
                                      context.t(option.labelKey),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: typo.uiTiny.copyWith(
                                        color:
                                            option.type != null &&
                                                commands.selectedType ==
                                                    option.type
                                            ? colors.accent
                                            : colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
