// 职责: 右栏属性区 — 按选中对象分派到角色 / 道具或机位属性；未选中时展示导演台属性。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/inspector/object.dart
//   lib/shared/widgets/director/inspector/camera.dart
//   lib/shared/widgets/director/inspector/stage.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules: .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../models/director/sampling.dart';
import '../../models/director/document.dart';
import 'strings.dart';
import '../../services/director/session.dart';
import '../../theme/theme.dart';
import 'inspector/camera.dart';
import 'inspector/object.dart';
import 'inspector/stage.dart';

class Inspector extends HookWidget {
  const Inspector({
    super.key,
    required this.session,
    required this.onAlignToView,
  });
  final DirectorSession session;

  /// 把某个机位对齐到导演视角当前位姿。
  final void Function(String cameraId) onAlignToView;

  @override
  Widget build(BuildContext context) {
    useListenable(session);
    useListenable(session.frame);
    final section = useState('properties');
    // 从时间轴或视口选中路径时直接切到运动轨迹分区。
    useOnListenableChange(session.pathEditor, () {
      if (session.pathEditor.active) {
        section.value = 'path';
      }
    });
    final document = session.history.visible;
    FrameSample? sample;
    DocumentError? failure;
    try {
      sample = sampleDocument(document, session.frame.value);
    } on DocumentError catch (error) {
      failure = error;
    }
    // Recovery shows authored values, not a substitute render or stale frame.
    Json authored(Json source) {
      final values = cloneJson(source);
      for (final track in document.propertyTracks.where(
        (t) => t.targetId == source['id'],
      )) {
        if (track.property != 'camera_target') {
          values[track.property] = samplePropertyTrack(
            track,
            session.frame.value,
            base: values[track.property],
          );
        }
      }
      return values;
    }

    final object = document.objects
        .where((o) => o['id'] == session.selected)
        .firstOrNull;
    final camera = document.camera(session.selected);
    return SingleChildScrollView(
      key: const ValueKey('director-inspector'),
      padding: const EdgeInsets.all(RevericSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            Text(
              tr(context, '${failure.path}: ${failure.reason}'),
              key: const ValueKey('director-inspector-diagnostic'),
              style: RevericTheme.typographyOf(
                context,
              ).uiSmall.copyWith(color: RevericTheme.colorsOf(context).error),
            ),
            Text(
              tr(context, 'recovery_fields'),
              style: RevericTheme.typographyOf(context).uiTiny,
            ),
            const SizedBox(height: RevericSpacing.sm),
          ],
          if (object != null)
            ObjectInspector(
              key: ValueKey('inspector:${object['id']}'),
              session: session,
              object: object,
              section: section.value,
              onSection: (value) => section.value = value,
              sampled:
                  sample?.objects.firstWhere((o) => o['id'] == object['id']) ??
                  authored(object),
            )
          else if (camera != null)
            CameraInspector(
              key: ValueKey('inspector:${camera['id']}'),
              session: session,
              camera: camera,
              sampled: sample?.cameras[camera['id']] ?? authored(camera),
              recovering: failure != null,
              onAlignToView: () => onAlignToView(camera['id']),
            )
          else
            StageInspector(session: session),
        ],
      ),
    );
  }
}
