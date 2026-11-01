// 职责: 在导演编辑区底部展示当前操作错误。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/workspace.dart
//   lib/shared/widgets/director/strings.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json

import 'package:flutter/material.dart';

import '../../services/director/session.dart';
import '../../theme/theme.dart';
import 'strings.dart';

class DirectorErrorStatus extends StatelessWidget {
  const DirectorErrorStatus({super.key, required this.session});
  final DirectorSession session;
  @override
  Widget build(BuildContext context) => session.error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
          child: Text(
            tr(context, session.error!),
            style: RevericTheme.typographyOf(context).uiSmall
                .copyWith(color: RevericTheme.colorsOf(context).error),
          ),
        );
}
