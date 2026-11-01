// 职责: 让退格先选中剧本角色行，并处理角色行或空正文的下一次退格。
// 关联文件:
//   lib/desktop/features/screenplay/script.dart
//   lib/mobile/features/screenplay/scene_editor.dart
//   lib/shared/utils/text_input_composing.dart
//   lib/shared/theme/theme.dart
//   lib/shared/widgets/screenplay/editing_scope.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../utils/text_input_composing.dart';
import '../../theme/theme.dart';
import 'editing_scope.dart';

class ScreenplayBackspaceTarget extends HookWidget {
  const ScreenplayBackspaceTarget({
    super.key,
    required this.onBackspace,
    required this.child,
    this.requestFocus = false,
  });

  final VoidCallback onBackspace;
  final Widget child;
  final bool requestFocus;

  @override
  Widget build(BuildContext context) {
    final focus = useFocusNode(skipTraversal: true);
    useListenable(focus);
    final colors = RevericTheme.colorsOf(context);
    final requested = useRef(requestFocus)..value = requestFocus;
    useEffect(() {
      if (requestFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && requested.value) {
            focus.requestFocus();
            // 已经可见的角色保持原位，仅在视口外时做最小幅度滚动。
            context.findRenderObject()?.showOnScreen();
          }
        });
      }
      return null;
    }, [requestFocus]);

    return Focus(
      focusNode: focus,
      onKeyEvent: (_, event) {
        if (ScreenplayEditingScope.maybeOf(
              context,
            )?.controller.crossesElements ??
            false) {
          return KeyEventResult.ignored;
        }
        final keyboard = HardwareKeyboard.instance;
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.backspace ||
            keyboard.isShiftPressed ||
            keyboard.isControlPressed ||
            keyboard.isAltPressed ||
            keyboard.isMetaPressed) {
          return KeyEventResult.ignored;
        }
        if (!focus.hasPrimaryFocus) {
          final editable = FocusManager.instance.primaryFocus?.context
              ?.findAncestorStateOfType<EditableTextState>();
          final controller = editable?.widget.controller;
          if (editable == null ||
              editable.widget.readOnly ||
              controller == null ||
              controller.text.isNotEmpty ||
              !controller.selection.isValid ||
              !controller.selection.isCollapsed ||
              isTextInputComposing(controller)) {
            return KeyEventResult.ignored;
          }
        }
        onBackspace();
        return KeyEventResult.handled;
      },
      child: CustomPaint(
        foregroundPainter: focus.hasPrimaryFocus
            ? _CharacterCaretPainter(context, colors.accent)
            : null,
        child: child,
      ),
    );
  }
}

/// 角色名不是可编辑文本，但被退格选中时仍在文字末尾画光标；覆盖绘制不挤动排版。
class _CharacterCaretPainter extends CustomPainter {
  const _CharacterCaretPainter(this.context, this.color);

  final BuildContext context;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final root = context.findRenderObject();
    if (root is! RenderBox) {
      return;
    }
    RenderParagraph? paragraph;
    void findParagraph(RenderObject object) {
      if (paragraph != null) {
        return;
      }
      if (object is RenderParagraph) {
        paragraph = object;
      } else {
        object.visitChildren(findParagraph);
      }
    }

    root.visitChildren(findParagraph);
    final text = paragraph;
    if (text == null) {
      return;
    }
    final position = TextPosition(offset: text.text.toPlainText().length);
    final offset = text.localToGlobal(
      text.getOffsetForCaret(position, Rect.zero),
      ancestor: root,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy,
        1.5,
        text.getFullHeightForCaret(position),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CharacterCaretPainter oldDelegate) =>
      oldDelegate.context != context || oldDelegate.color != color;
}
