// 职责: 用单字符内联标签编辑资源引用，并在剪贴板与持久化边界还原 ref 协议。
// 关联文件:
//   lib/shared/models/storyboard/prompt.dart
//   lib/desktop/features/production/composer.dart
import 'package:flutter/material.dart';
import '../../../shared/models/storyboard/prompt.dart';
import '../../../shared/theme/theme.dart';

class ProductionPromptController extends TextEditingController {
  ProductionPromptController(String source) {
    text = encode(source);
  }
  final _references = <String, PromptPart>{};
  Set<String> inputIds = {};
  void Function(String)? onPreview;
  String encode(String source) =>
      StoryboardPrompt.parse(source).parts.map((part) {
        if (!part.isReference) {
          return part.text;
        }
        final code = String.fromCharCode(0xe000 + _references.length);
        if (_references.length >= 6400) {
          throw const FormatException('Too many references');
        }
        _references[code] = part;
        return code;
      }).join();
  String decode(String text) =>
      text.split('').map((c) => _references[c]?.text ?? c).join();
  String get source => decode(text);

  /// Visible text remains readable while the user is typing an incomplete tag.
  String get plainText =>
      text.split('').map((c) => _references[c]?.label ?? c).join();
  void insertReference(String id, String label) {
    final selection = this.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final at = start > 0 && text[start - 1] == '@' ? start - 1 : start;
    final encoded = encode(StoryboardPrompt.reference(id, label));
    value = TextEditingValue(
      text: text.replaceRange(at, end, encoded),
      selection: TextSelection.collapsed(offset: at + encoded.length),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final spans = <InlineSpan>[];
    for (var i = 0; i < text.length; i++) {
      final ref = _references[text[i]];
      if (ref == null) {
        spans.add(
          TextSpan(
            text: text[i],
            style:
                withComposing &&
                    value.composing.isValid &&
                    i >= value.composing.start &&
                    i < value.composing.end
                ? (style ?? typo.bodySmall).copyWith(
                    decoration: TextDecoration.underline,
                  )
                : null,
          ),
        );
      } else {
        final valid = inputIds.contains(ref.inputId);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () => onPreview?.call(ref.inputId!),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  borderRadius: BorderRadius.circular(RevericRadius.large),
                ),
                child: Text(
                  '@${ref.label}',
                  style: typo.uiSmall.copyWith(
                    color: valid ? colors.accent : colors.error,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return TextSpan(style: style, children: spans);
  }
}
