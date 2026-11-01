// 职责: 小剧场「转到写作」按钮 — 菜单里选写成正文（第三人称或某角色视角）或只带剧本，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/models/theater_models.dart
//   lib/desktop/features/theater/performance_section.dart
//   lib/mobile/features/theater/page_widgets.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/theater.json
//   assets/translations/zh-CN/theater.json
import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/reveric_context_menu.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/theater_models.dart';
import '../../theme/theme.dart';

class TheaterWriteButton extends StatelessWidget {
  const TheaterWriteButton({
    super.key,
    required this.session,
    required this.onWrite,
  });

  final TheaterSession session;

  /// 传 null 表示禁用。参数是带入 chat 的写作指令；只带剧本时为 null。
  final ValueChanged<String?>? onWrite;

  @override
  Widget build(BuildContext context) {
    final write = onWrite;
    return OutlinedButton.icon(
      onPressed: write == null ? null : () => _showMenu(context, write),
      icon: RevericIcon(RevericIcons.edit_note_outlined, size: 16),
      label: Text(context.t(LocaleKeys.aiSwitchToWriteMode)),
    );
  }

  void _showMenu(BuildContext context, ValueChanged<String?> write) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    unawaited(
      showRevericContextMenu(
        context: context,
        position: Offset(
          origin.dx,
          origin.dy + box.size.height + RevericSpacing.xs,
        ),
        entries: [
          RevericMenuItem(
            label: context.t(LocaleKeys.theaterWriteProseThird),
            icon: RevericIcons.edit_note_outlined,
            onTap: () => write(buildTheaterProseInstruction()),
          ),
          for (final p in session.participants)
            RevericMenuItem(
              label: context.t(
                LocaleKeys.theaterWriteProsePovFmt,
                namedArgs: {'name': p.name},
              ),
              icon: RevericIcons.person_outline,
              onTap: () =>
                  write(buildTheaterProseInstruction(povCharacterName: p.name)),
            ),
          const RevericMenuDivider(),
          RevericMenuItem(
            label: context.t(LocaleKeys.theaterWriteTranscriptOnly),
            icon: RevericIcons.theater_comedy_rounded,
            onTap: () => write(null),
          ),
        ],
      ),
    );
  }
}
