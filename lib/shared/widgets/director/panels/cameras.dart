// 职责: 机位面板 — 列出机位并按构图预设围绕选中角色添加新机位。
// 关联文件:
//   lib/shared/models/director/presets.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/widgets/director/panels/common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
import 'package:flutter/material.dart';

import '../../../models/director/presets.dart';
import '../../../services/director/session.dart';
import '../../../theme/theme.dart';
import '../strings.dart';
import 'common.dart';

class DirectorCamerasPanel extends StatelessWidget {
  const DirectorCamerasPanel({
    super.key,
    required this.session,
    required this.onAlignToView,
  });
  final DirectorSession session;

  /// 「当前视角」预设：用导演视角的位姿新建机位。
  final void Function(String name) onAlignToView;

  @override
  Widget build(BuildContext context) {
    final document = session.history.document;
    final cameras = document.activeCameras;
    final subject = document.objects
        .where((o) => o['id'] == session.selected && o['kind'] == 'actor')
        .firstOrNull;
    // 「预设名_序号」，同一预设内递增并跳过已有名称（含已删除机位）。
    String nextName(String preset) {
      final names = {for (final c in document.cameras) c['name']};
      for (var i = 1; ; i++) {
        final name = trArgs(context, 'camera_name', {
          'preset': tr(context, 'preset_$preset'),
          'index': '$i',
        });
        if (!names.contains(name)) {
          return name;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelTitle(tr(context, 'cameras')),
        for (final c in cameras)
          PanelRow(
            key: ValueKey('director-camera:${c['id']}'),
            title: c['name'],
            icon: RevericIcons.video_camera,
            subtitle: '${c['focal_length_mm']}mm',
            selected: session.selected == c['id'],
            onTap: () => session.select(c['id']),
            menu: () => objectMenu(context, session, c['id']),
          ),
        PanelTitle(tr(context, 'add_camera'), top: RevericSpacing.lg),
        TwoColumnGrid(
          children: [
            for (final p in cameraPresets)
              PresetCard(
                key: ValueKey('director-camera-preset:$p'),
                title: tr(context, 'preset_$p'),
                icon: RevericIcons.video_camera,
                selected: false,
                onTap: cameras.length >= 8
                    ? null
                    : () => session.attempt(() {
                        if (p == 'current') {
                          onAlignToView(nextName(p));
                          return;
                        }
                        session.select(
                          session.history.addCamera(
                            nextName(p),
                            p,
                            subject?['id'],
                            session.frame.value,
                          ),
                        );
                      }),
              ),
          ],
        ),
      ],
    );
  }
}
