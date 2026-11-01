// 职责: 按结构化类型展示只读剧本正文元素。
// 关联文件:
//   lib/shared/widgets/screenplay/element_layout.dart
//   lib/shared/widgets/screenplay/text_styles.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/material.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/screenplay_element.dart';
import 'element_layout.dart';
import 'text_styles.dart';
import '../../theme/theme.dart';

class ScreenplayReadonlyElement extends StatelessWidget {
  const ScreenplayReadonlyElement({
    super.key,
    required this.element,
    required this.characterNames,
    required this.styles,
    required this.accent,
  });

  final ScreenplayElement element;
  final Map<String, String> characterNames;
  final ScreenplayTextStyles styles;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final child = switch (element.type) {
      ScreenplayElementType.scene_heading => throw ArgumentError(
        'Use a document heading row.',
      ),
      ScreenplayElementType.character => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  characterNames[element.characterId] ??
                  context.t(LocaleKeys.screenplayDeletedCharacter),
              style: characterNames.containsKey(element.characterId)
                  ? null
                  : styles.character.copyWith(
                      color: RevericTheme.colorsOf(context).warningText,
                    ),
            ),
            if (element.extension.isNotEmpty)
              TextSpan(
                text: '（${element.extension}）',
                style: styles.characterExtension,
              ),
            const TextSpan(text: '：'),
          ],
        ),
        style: styles.character,
      ),
      ScreenplayElementType.parenthetical => Text(
        '（${element.text}）',
        style: styles.parenthetical,
      ),
      ScreenplayElementType.dialogue => Text(
        element.text,
        style: styles.dialogue,
      ),
      ScreenplayElementType.transition => Text(
        element.text,
        textAlign: TextAlign.right,
        style: styles.transition,
      ),
      ScreenplayElementType.subtitle => _SubtitleBox(
        child: Text(element.text, style: styles.subtitle),
      ),
      ScreenplayElementType.note => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${context.t(LocaleKeys.screenplayNotePrefix)} ',
              style: styles.notePrefix,
            ),
            TextSpan(text: element.text),
          ],
        ),
        style: styles.note,
      ),
      ScreenplayElementType.action => Text(element.text, style: styles.action),
    };
    return ScreenplayElementLayout(
      type: element.type,
      isCaret: false,
      topSpacing: screenplayElementTopSpacing(element.type),
      child: child,
    );
  }
}

/// 字幕：短则收缩到文字宽度看起来是居中的，长则撑到上限、内部左对齐不出毛边。
/// 一个盒子同时表达两种状态，不需要判断长度。
class _SubtitleBox extends StatelessWidget {
  const _SubtitleBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 352),
          child: child,
        ),
      ),
    );
  }
}
