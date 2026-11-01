// 职责: 绑定剧本文字节点的原生输入、软换行与输入法组合状态。
// 关联文件:
//   lib/shared/widgets/screenplay/editing_scope.dart
//   lib/shared/models/screenplay_editing.dart
//   lib/shared/utils/text_input_composing.dart
// 遵循的 Rules:
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/screenplay_editing.dart';
import '../../utils/text_input_composing.dart';
import '../../theme/theme.dart';
import 'editing_scope.dart';

class ScreenplayElementField extends StatefulWidget {
  const ScreenplayElementField({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.onChanged,
    required this.onFocused,
    required this.onEnter,
    required this.onTab,
    this.autofocus = false,
    this.focusAtEnd = false,
    this.onEmptyBackspace,
    this.prefix = '',
    this.suffix = '',
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final ValueChanged<String> onChanged;
  final VoidCallback onFocused;
  final ValueChanged<String> onEnter;
  final bool autofocus;
  final bool focusAtEnd;
  final VoidCallback? onEmptyBackspace;
  final ValueChanged<bool> onTab;

  /// 括号提示的全角括号由渲染层补，不写进数据。
  final String prefix;
  final String suffix;

  @override
  State<ScreenplayElementField> createState() => _ScreenplayElementFieldState();
}

class _ScreenplayElementFieldState extends State<ScreenplayElementField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    if (widget.autofocus) {
      _controller.selection = TextSelection.collapsed(
        offset: widget.focusAtEnd ? _controller.text.length : 0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ScreenplayElementField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus &&
        !_focusNode.hasFocus &&
        (!oldWidget.autofocus ||
            (widget.focusAtEnd && !oldWidget.focusAtEnd))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.selection = TextSelection.collapsed(
            offset: widget.focusAtEnd ? _controller.text.length : 0,
          );
          _focusNode.requestFocus();
        }
      });
    }

    // 外部（AI 写入、切换场次后重新载入）改了正文时才回灌；本地正在编辑或
    // 正在组词时不动 controller，否则光标会跳、IME 会断。
    if (widget.text != _controller.text &&
        !_focusNode.hasFocus &&
        !isTextInputComposing(_controller)) {
      _controller.text = widget.text;
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocused();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    // 组词期间不劫持按键 —— Enter / Tab 那时属于输入法，不属于编辑器。
    if (isTextInputComposing(_controller)) {
      return KeyEventResult.ignored;
    }
    final editor = ScreenplayEditingScope.maybeOf(context)?.controller;
    if (editor != null &&
        (editor.crossesElements ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.tab)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty &&
        _controller.selection.isCollapsed &&
        widget.onEmptyBackspace != null) {
      widget.onEmptyBackspace!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final value = _controller.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      final split = splitScreenplayText(value.text, start, end);
      final before = split.before;
      final after = split.after;
      if (keyboard.isShiftPressed) {
        _controller.value = TextEditingValue(
          text: '$before\n$after',
          selection: TextSelection.collapsed(offset: before.length + 1),
        );
        widget.onChanged(_controller.text);
        return KeyEventResult.handled;
      }
      _controller.value = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      widget.onChanged(before);
      widget.onEnter(after);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.onTab(keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final field = TextField(
      contextMenuBuilder: screenplayContextMenuBuilder,
      controller: _controller,
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: null,
      cursorColor: colors.accent,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: widget.onChanged,
    );

    if (widget.prefix.isEmpty && widget.suffix.isEmpty) {
      return Focus(onKeyEvent: _handleKey, child: field);
    }

    // 前缀不能走 `InputDecoration.prefixText`：Flutter 把它的透明度绑在
    // `_labelShouldWithdraw`（非空或聚焦）上，空括号行失焦时左括号被画成透明，
    // 只剩自己画的右括号，看起来像半只括号。
    //
    // 后缀也不能走 `InputDecoration.suffixText`：输入区会占满整行宽度，右括号
    // 被推到行尾，看起来像和文字断开的一只孤括号。改成把输入框收到内容宽度，
    // 括号紧跟其后；行内空白交给外层 GestureDetector 回焦，点哪儿都能继续写。
    Widget body = widget.suffix.isEmpty
        ? field
        : Row(
            // 文字换行时右括号跟到最后一行，而不是留在第一行的行尾。
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: IntrinsicWidth(child: field)),
              Text(widget.suffix, style: widget.style),
            ],
          );
    if (widget.prefix.isNotEmpty) {
      body = Row(
        // 左括号留在第一行，与右括号跟到末行相反，所以两者不能共用一个 Row。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.prefix, style: widget.style),
          Flexible(child: body),
        ],
      );
    }

    return Focus(
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focusNode.requestFocus,
        child: body,
      ),
    );
  }
}
