// 职责: A2UI 展示组件 Text、Markdown、Icon、Loading 的 builder。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/widgets/ai/markdown_text.dart
//   lib/shared/components/reveric_spinner.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../../../components/reveric_spinner.dart';
import '../../../theme/theme.dart';
import '../../ai/markdown_text.dart';
import '../component.dart';

/// 出现这些标记才走 Markdown 排版；纯文本直接用 [Text]，长列表里更省。
final _markdownHint = RegExp(
  r'[*_`#>\[~|]|^\s*(?:[-+]|\d+\.)\s',
  multiLine: true,
);

Widget buildText(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  final text = props.string('text') ?? '';
  final style = props.string('variant') == 'caption'
      ? typo.uiSmall.copyWith(color: colors.textMuted)
      : typo.ui.copyWith(color: colors.textPrimary);
  if (!_markdownHint.hasMatch(text)) {
    return Text(text, style: style);
  }
  return AiMarkdownText(text, style: style, selectable: false);
}

Widget buildMarkdown(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  return AiMarkdownText(
    props.string('text') ?? '',
    style: typo.ui.copyWith(color: colors.textPrimary),
  );
}

/// A2UI 基础目录的图标名到 Phosphor 图标的映射。
const a2uiIconAssets = <String, String>{
  'accountCircle': RevericIcons.user_circle,
  'add': RevericIcons.add,
  'arrowBack': RevericIcons.arrow_back,
  'arrowForward': RevericIcons.arrow_forward,
  'attachFile': RevericIcons.attachment,
  'calendarToday': RevericIcons.calendar_blank,
  'call': RevericIcons.phone,
  'camera': RevericIcons.camera,
  'check': RevericIcons.check,
  'close': RevericIcons.close,
  'delete': RevericIcons.delete,
  'download': RevericIcons.download,
  'edit': RevericIcons.edit,
  'event': RevericIcons.calendar_dots,
  'error': RevericIcons.warning_circle,
  'fastForward': RevericIcons.fast_forward,
  'favorite': RevericIcons.favorite,
  'favoriteOff': RevericIcons.heart_break,
  'folder': RevericIcons.folder_outlined,
  'help': RevericIcons.help_outline,
  'home': RevericIcons.home,
  'info': RevericIcons.info,
  'locationOn': RevericIcons.location_on,
  'lock': RevericIcons.lock_outline,
  'lockOpen': RevericIcons.lock_open_outlined,
  'mail': RevericIcons.envelope,
  'menu': RevericIcons.list_alt_outlined,
  'moreVert': RevericIcons.more_vert,
  'moreHoriz': RevericIcons.more_horiz,
  'notificationsOff': RevericIcons.bell_slash,
  'notifications': RevericIcons.bell,
  'pause': RevericIcons.pause,
  'payment': RevericIcons.credit_card,
  'person': RevericIcons.person,
  'phone': RevericIcons.phone,
  'photo': RevericIcons.image,
  'play': RevericIcons.play_arrow,
  'print': RevericIcons.printer,
  'refresh': RevericIcons.arrows_clockwise,
  'rewind': RevericIcons.rewind,
  'search': RevericIcons.search,
  'send': RevericIcons.send_rounded,
  'settings': RevericIcons.settings_outlined,
  'share': RevericIcons.share_outlined,
  'shoppingCart': RevericIcons.shopping_cart,
  'skipNext': RevericIcons.skip_forward,
  'skipPrevious': RevericIcons.skip_back,
  'star': RevericIcons.star,
  'starHalf': RevericIcons.star_half,
  // Phosphor 没有「星标关闭」，与 star 共用空心星。
  'starOff': RevericIcons.star,
  'stop': RevericIcons.stop_rounded,
  'upload': RevericIcons.upload,
  'visibility': RevericIcons.visibility,
  'visibilityOff': RevericIcons.visibility_off,
  'volumeDown': RevericIcons.speaker_low,
  'volumeMute': RevericIcons.speaker_none,
  'volumeOff': RevericIcons.speaker_slash,
  'volumeUp': RevericIcons.speaker_high,
  'warning': RevericIcons.warning,
};

/// 图标名对应的资源；未知名称或 `svgPath` 自绘图标退回帮助图标。
String a2uiIconAsset(String? name) =>
    a2uiIconAssets[name] ?? RevericIcons.help_outline;

Widget buildIcon(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  return RevericIcon(
    a2uiIconAsset(props.string('name')),
    size: 20,
    color: colors.textSecondary,
  );
}

Widget buildLoading(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  final label = props.string('label');
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 16,
        child: RevericSpinner(color: colors.accent),
      ),
      if (label != null && label.isNotEmpty) ...[
        const SizedBox(width: RevericSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    ],
  );
}
