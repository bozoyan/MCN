// 职责: 在当前帧无法求值时显示诊断，阻止无效数据进入原生视口。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/services/director/session.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules: .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../components/reveric_placeholder.dart';
import '../../models/director/document.dart';
import '../../models/director/sampling.dart';
import '../../services/director/session.dart';
import 'strings.dart';

class DirectorFrameContent extends HookWidget {
  const DirectorFrameContent({
    super.key,
    required this.session,
    required this.builder,
  });
  final DirectorSession session;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    useListenable(session.history);
    useListenable(session.frame);
    try {
      sampleDocument(session.history.visible, session.frame.value);
    } on DocumentError catch (error) {
      return Center(
        child: SingleChildScrollView(
          child: RevericPlaceholder.error(
            key: const ValueKey('director-frame-diagnostic'),
            title: tr(context, 'frame_unavailable'),
            description: tr(context, '${error.path}: ${error.reason}'),
            compact: true,
          ),
        ),
      );
    }
    return builder(context);
  }
}
