// 职责: 导演台属性 — 编辑整个工程共用的时长、开场机位与切镜、灯光，未选中对象时展示。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/inspector/cuts.dart
//   lib/shared/widgets/director/inspector/lighting.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../services/director/session.dart';
import '../../../theme/theme.dart';
import '../strings.dart';
import 'controls.dart';
import 'cuts.dart';
import 'lighting.dart';

class StageInspector extends StatelessWidget {
  const StageInspector({super.key, required this.session});
  final DirectorSession session;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final document = session.history.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RevericIcon(
              RevericIcons.movie_outlined,
              size: RevericSizes.buttonIconSize,
              color: colors.textMuted,
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                tr(context, 'title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSemibold,
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        LabeledField(
          label: tr(context, 'duration'),
          child: CommitField(
            fieldKey: const ValueKey('director-field:duration'),
            session: session,
            suffix: tr(context, 'seconds_unit'),
            value: (document.durationFrames / document.fps).toStringAsFixed(1),
            enabled: !session.playing,
            onCommit: (text) {
              final v = double.tryParse(text);
              return v != null &&
                  commitEdit(
                    session,
                    () => session.history.execute(
                      (j) => j['duration_frames'] = (v * document.fps).round(),
                    ),
                  );
            },
          ),
        ),
        CameraCutsInspector(session: session),
        LightingInspector(session: session),
      ],
    );
  }
}
