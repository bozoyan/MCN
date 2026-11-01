// 职责: 道具面板 — 以卡片网格列出可添加的道具模板，点击即添加到场景。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/panels/common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'package:flutter/material.dart';

import '../../../services/director/session.dart';
import '../../../models/director/presets.dart';
import '../../../theme/theme.dart';
import '../strings.dart';
import 'common.dart';

class DirectorPropsPanel extends StatelessWidget {
  const DirectorPropsPanel({super.key, required this.session});
  final DirectorSession session;

  @override
  Widget build(BuildContext context) {
    final document = session.history.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in propGroups) ...[
          PanelTitle(tr(context, 'props_$group'), top: RevericSpacing.sm),
          TwoColumnGrid(
            children: [
              for (final prop in propPresets.where((p) => p.group == group))
                PresetCard(
                  key: ValueKey('director-prop:${prop.geometry}'),
                  title: tr(context, 'prop_${prop.name}'),
                  icon: RevericIcons.cube,
                  selected: false,
                  onTap: () => session.attempt(
                    () => session.history.addObject(
                      prop.geometry,
                      '${tr(context, 'prop_${prop.name}')} ${document.objects.length + 1}',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
