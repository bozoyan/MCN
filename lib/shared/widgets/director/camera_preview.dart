// 职责: 视口内悬浮机位预览 — 切换预览机位、可折叠，按画幅持续渲染该机位取景，隔离主视口编辑手势。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/services/director/session.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules: .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_icon_button.dart';
import '../../components/reveric_select.dart';
import '../../services/director/session.dart';
import '../../theme/theme.dart';
import 'strings.dart';
import 'viewport.dart';

class DirectorCameraPreview extends HookWidget {
  const DirectorCameraPreview({
    super.key,
    required this.session,
    this.viewportBuilder,
  });
  final DirectorSession session;
  final Widget Function(DirectorSession, ViewState)? viewportBuilder;
  @override
  Widget build(BuildContext context) {
    final view = useMemoized(() => ViewState()..output = true);
    final expanded = useState(true);
    useEffect(() => view.dispose, [view]);
    useListenable(session);
    final colors = RevericTheme.colorsOf(context);
    final document = session.history.document;
    final cameras = document.activeCameras;
    final current = session.cameraMode == 'sequence'
        ? ''
        : session.viewCameraId;
    final header = Padding(
      padding: const EdgeInsets.all(RevericSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(
                child: RevericSelect<String>(
                  value: current,
                  height: RevericSizes.fieldHeightSm,
                  menuWidth: RevericSizes.directorModeSwitchWidth,
                  leadingIcon: RevericIcons.video_camera,
                  items: [
                    RevericSelectItem(
                      value: '',
                      label: tr(context, 'sequence'),
                    ),
                    for (final c in cameras)
                      RevericSelectItem(value: c['id'], label: c['name']),
                  ],
                  onChanged: (id) => session.viewCamera(id.isEmpty ? null : id),
                ),
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border.all(color: colors.borderInput),
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: RevericIconButton(
              key: const ValueKey('director-camera-preview-toggle'),
              icon: expanded.value
                  ? RevericIcons.expand_less_rounded
                  : RevericIcons.caret_down,
              tooltip: tr(context, 'camera_preview'),
              onPressed: () => expanded.value = !expanded.value,
            ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('director-camera-preview'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      // 展开时画面铺满整窗，机位下拉和折叠按钮浮在画面上方；折叠后只留这一行。
      child: !expanded.value
          ? header
          : Stack(
              children: [
                // 固定 16:9 小窗，成片画幅在其中留白；细看切到机位视角。
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child:
                          viewportBuilder?.call(session, view) ??
                          DirectorViewport(
                            session: session,
                            view: view,
                            preview: true,
                          ),
                    ),
                  ),
                ),
                Positioned(top: 0, left: 0, right: 0, child: header),
              ],
            ),
    );
  }
}
