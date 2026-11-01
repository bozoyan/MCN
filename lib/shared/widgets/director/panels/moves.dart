// 职责: 运镜面板 — 把运镜预设套用到选中机位的时间轴选区。
// 关联文件:
//   lib/shared/models/director/presets.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/widgets/director/panels/common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules: .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../components/reveric_checkbox.dart';
import '../../../components/reveric_button.dart';

import '../../../models/director/presets.dart';
import '../../../services/director/session.dart';
import '../../../theme/theme.dart';
import '../strings.dart';
import 'common.dart';

class DirectorMovesPanel extends HookWidget {
  const DirectorMovesPanel({super.key, required this.session});
  final DirectorSession session;

  @override
  Widget build(BuildContext context) {
    final replace = useState(false);
    final colors = RevericTheme.colorsOf(context);
    final document = session.history.document;
    final camera = document.camera(session.selected);
    final (start, end) = session.range;
    final covering = camera == null
        ? null
        : document.moves
              .where(
                (m) =>
                    m['camera_id'] == camera['id'] &&
                    m['start_frame'] <= start &&
                    m['end_frame'] >= end,
              )
              .firstOrNull;
    final hasSubject =
        camera?['orientation_mode'] == 'look_at' &&
        camera?['camera_target']['type'] != 'point';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TargetBar(
          session: session,
          name: camera?['name'],
          icon: RevericIcons.video_camera,
          empty: tr(context, 'select_camera'),
          trailing: Tooltip(
            message: tr(context, 'path_replace'),
            child: MergeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => replace.value = !replace.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RevericCheckbox(
                      value: replace.value,
                      onChanged: (value) => replace.value = value,
                    ),
                    Text(
                      tr(context, 'replace_short'),
                      style: RevericTheme.typographyOf(
                        context,
                      ).uiSmall.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (covering != null)
          Wrap(
            children: [
              RevericButton.text(
                label: tr(context, 'bake'),
                size: RevericButtonSize.compact,
                onPressed: () => session.attempt(
                  () => session.history.bake('camera_moves', covering['id']),
                ),
              ),
              RevericButton.text(
                label: tr(context, 'delete'),
                size: RevericButtonSize.compact,
                onPressed: () => session.attempt(
                  () => session.history.execute(
                    (j) => (j['camera_moves'] as List).removeWhere(
                      (m) => m['id'] == covering['id'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        for (final g in moveGroups) ...[
          PanelTitle(
            tr(context, 'group_$g'),
            top: RevericSpacing.xs,
            note:
                camera != null &&
                    !hasSubject &&
                    movePresets.every((m) => m.group != g || m.subject)
                ? tr(context, 'needs_subject')
                : null,
          ),
          TwoColumnGrid(
            children: [
              for (final m in movePresets.where((m) => m.group == g))
                PresetCard(
                  key: ValueKey('director-move:${m.id}'),
                  title: tr(context, 'move_${m.id}'),
                  icon: _baseIcons[m.base],
                  tooltip: m.subject && !hasSubject
                      ? '${tr(context, 'move_desc_${m.id}')}\n${tr(context, 'needs_subject')}'
                      : tr(context, 'move_desc_${m.id}'),
                  selected: covering?['kind'] == m.id,
                  onTap: camera == null || (m.subject && !hasSubject)
                      ? null
                      : () => session.attempt(
                          () => session.history.move(
                            camera['id'],
                            m.id,
                            start,
                            end,
                            replace: replace.value,
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
        ],
      ],
    );
  }
}

/// 运镜大类的示意图标：卡片按类别一眼可辨，具体方向看名称。
const _baseIcons = {
  'static': RevericIcons.lock_simple,
  'pan': RevericIcons.arrows_horizontal,
  'tilt': RevericIcons.arrows_vertical,
  'push': RevericIcons.arrows_in,
  'pull': RevericIcons.arrows_out,
  'track': RevericIcons.alt_route_outlined,
  'crane': RevericIcons.arrow_fat_lines_up,
  'orbit': RevericIcons.arrows_clockwise,
  'focus': RevericIcons.aperture,
};
