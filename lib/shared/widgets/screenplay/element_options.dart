// 职责: 统一两端剧本元素类型的标签、图标和默认续写类型。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../models/screenplay_element.dart';
export '../../models/screenplay_editing.dart' show screenplayNextElementType;
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

/// 元素工具条上的一格。[type] 为 null 的那一格是「场次」——
/// 标题不参与普通类型轮转，所以这一格执行插入标题与拆场命令。
class ScreenplayElementOption {
  const ScreenplayElementOption({
    required this.type,
    required this.icon,
    required this.labelKey,
  });

  final ScreenplayElementType? type;
  final String icon;
  final String labelKey;
}

const screenplayElementDigitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

bool get screenplayUsesMetaShortcuts =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

String screenplayElementShortcutLabel(int number) =>
    '${screenplayUsesMetaShortcuts ? '⌘' : 'Ctrl+'}$number';

/// 顺序即 ⌘1..⌘8，也是 Tab 循环的顺序（普通类型轮转跳过场次命令）。
///
/// 前六格沿用 Final Draft 的 ⌘1..⌘6（场次 / 动作 / 角色 / 括号 / 对话 / 转场），
/// 这也正好是角色—括号—对话在页面上从上到下的堆叠顺序。末两格里字幕是正片内容、
/// 注释只是写作批注，所以字幕在前。
const List<ScreenplayElementOption> screenplayElementOptions = [
  ScreenplayElementOption(
    type: null,
    icon: RevericIcons.space_dashboard_outlined,
    labelKey: LocaleKeys.screenplayElementScene,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.action,
    icon: RevericIcons.water,
    labelKey: LocaleKeys.screenplayElementAction,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.character,
    icon: RevericIcons.person,
    labelKey: LocaleKeys.screenplayElementCharacter,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.parenthetical,
    icon: RevericIcons.format_quote,
    labelKey: LocaleKeys.screenplayElementParenthetical,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.dialogue,
    icon: RevericIcons.chat_outlined,
    labelKey: LocaleKeys.screenplayElementDialogue,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.transition,
    icon: RevericIcons.arrow_forward,
    labelKey: LocaleKeys.screenplayElementTransition,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.subtitle,
    icon: RevericIcons.text_fields_outlined,
    labelKey: LocaleKeys.screenplayElementSubtitle,
  ),
  ScreenplayElementOption(
    type: ScreenplayElementType.note,
    icon: RevericIcons.edit_note_outlined,
    labelKey: LocaleKeys.screenplayElementNote,
  ),
];
