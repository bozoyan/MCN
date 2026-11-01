// 职责: 将整场编辑命令、剪贴板、键鼠选区与查找替换接到剧本元素输入框。
// 关联文件:
//   lib/shared/widgets/screenplay/editing_controller.dart
//   lib/shared/widgets/screenplay/editing_row.dart
//   lib/shared/widgets/text_find_replace_scope.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/text-input-ime.md
//   .agents/rules/search-debounce.md

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/screenplay_element.dart';
import '../confirm_dialog.dart';
import '../text_find_replace_scope.dart';
import 'editing_controller.dart';
import 'editing_row.dart';

class ScreenplayEditingScope extends StatefulWidget {
  const ScreenplayEditingScope({
    super.key,
    required this.controller,
    required this.child,
    required this.onFocusElement,
    this.onCycleType,
  });
  final ScreenplayEditingController controller;
  final Widget child;
  final void Function(int index, bool atEnd) onFocusElement;
  final ValueChanged<bool>? onCycleType;

  static ScreenplayEditingScopeState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EditingScope>()!.state;
  static ScreenplayEditingScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EditingScope>()?.state;

  @override
  State<ScreenplayEditingScope> createState() => ScreenplayEditingScopeState();
}

// State 成对管理真实输入节点的注册、帧后同步，以及更换场次控制器时的解绑。
class ScreenplayEditingScopeState extends State<ScreenplayEditingScope> {
  final _focus = FocusNode(skipTraversal: true);
  final _rows = <ScreenplayEditingRowState>{};
  bool _scheduled = false;
  bool _requestFocus = false;
  double? _preferredX;
  bool _initialEmptyFocus = false;
  int? _mousePointer;
  ScreenplayEditingRowState? _mouseStartRow;
  int? _mouseAnchor;
  Offset? _mousePosition;
  bool _selectingWithMouse = false;
  EdgeDraggingAutoScroller? _mouseScroller;
  bool get selectingWithMouse => _selectingWithMouse;
  ScreenplayEditingController get controller => widget.controller;
  void resetHorizontalAnchor() => _preferredX = null;

  void _mouseDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton ||
        controller.isComposing) {
      return;
    }
    // 只从正文输入区发起；角色按钮、删除按钮及场次标题保留自己的点击行为。
    for (final row in _rows) {
      final render = row.editable?.renderEditable;
      final box = render ?? row.context.findRenderObject();
      final heading =
          row.index < controller.value.length &&
          controller.value[row.index].isHeading;
      if (box is! RenderBox ||
          !box.attached ||
          !(Offset.zero & box.size).contains(
            box.globalToLocal(event.position),
          ) ||
          (render == null && !heading)) {
        continue;
      }
      _stopMouseSelection();
      _mousePointer = event.pointer;
      _mouseStartRow = row;
      _mouseAnchor = HardwareKeyboard.instance.isShiftPressed
          ? controller.selection.baseOffset
          : controller.startOf(row.index) +
                (render?.getPositionForPoint(event.position).offset ?? 0);
      _mousePosition = event.position;
      final scrollable = Scrollable.maybeOf(row.context, axis: Axis.vertical);
      if (scrollable != null) {
        _mouseScroller = EdgeDraggingAutoScroller(
          scrollable,
          velocityScalar: 20,
          onScrollViewScrolled: _updateMouseSelection,
        );
      }
      return;
    }
  }

  void _mouseMove(PointerMoveEvent event) {
    if (event.pointer != _mousePointer) {
      return;
    }
    _mousePosition = event.position;
    _updateMouseSelection();
  }

  void _updateMouseSelection() {
    final point = _mousePosition;
    final anchor = _mouseAnchor;
    if (point == null || anchor == null || !mounted) {
      return;
    }
    ScreenplayEditingRowState? target;
    var distance = double.infinity;
    for (final row in _rows) {
      final box =
          row.editable?.renderEditable ?? row.context.findRenderObject();
      if (!row.mounted ||
          row.index >= controller.value.length ||
          box is! RenderBox ||
          !box.attached ||
          !box.hasSize) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final nextDistance = point.dy < rect.top
          ? rect.top - point.dy
          : point.dy > rect.bottom
          ? point.dy - rect.bottom
          : 0.0;
      if (nextDistance < distance) {
        target = row;
        distance = nextDistance;
      }
    }
    if (target == null) {
      return;
    }
    // 同一输入框内仍用原生单击、双击选词与拖选；跨行后由整场选区接管到松开。
    if (!_selectingWithMouse && target == _mouseStartRow) {
      return;
    }
    _selectingWithMouse = true;
    _preferredX = null;
    final render = target.editable?.renderEditable;
    final local = render?.getPositionForPoint(point);
    final box = target.context.findRenderObject()! as RenderBox;
    final offset =
        local?.offset ??
        (point.dx < box.localToGlobal(box.size.center(Offset.zero)).dx ? 0 : 1);
    controller.select(
      TextSelection(
        baseOffset: anchor,
        extentOffset: controller.startOf(target.index) + offset,
        affinity: local?.affinity ?? TextAffinity.downstream,
      ),
      requestFocus: false,
    );
    final scroller = _mouseScroller;
    if (scroller != null) {
      final viewport =
          scroller.scrollable.context.findRenderObject()! as RenderBox;
      scroller.startAutoScrollIfNecessary(
        Rect.fromCenter(
          center: viewport.globalToLocal(point),
          width: 1,
          height: 1,
        ),
      );
    }
  }

  void _mouseEnd(PointerEvent event) {
    if (event.pointer != _mousePointer) {
      return;
    }
    _mouseScroller?.stopAutoScroll();
    // 等同一 pointer 事件中的原生拖选回调结束，再交还输入框并把焦点移到选区终点。
    scheduleMicrotask(() {
      if (!mounted || event.pointer != _mousePointer) {
        return;
      }
      final focusSelection = _selectingWithMouse;
      _stopMouseSelection();
      if (focusSelection) {
        controller.select(controller.selection);
      }
    });
  }

  void _stopMouseSelection() {
    _mouseScroller?.stopAutoScroll();
    _mouseScroller = null;
    _mousePointer = null;
    _mouseStartRow = null;
    _mouseAnchor = null;
    _mousePosition = null;
    _selectingWithMouse = false;
  }

  @override
  void initState() {
    super.initState();
    _initialEmptyFocus = controller.value.isEmpty;
    controller.document.addListener(_scheduleSync);
    controller.onSelectionRequested = _focusSelection;
    _focus.addListener(_rootFocusChanged);
  }

  void register(ScreenplayEditingRowState row) {
    _rows.add(row);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(ScreenplayEditingScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      _stopMouseSelection();
      oldWidget.controller.document.removeListener(_scheduleSync);
      oldWidget.controller.onSelectionRequested = null;
      controller.document.addListener(_scheduleSync);
      controller.onSelectionRequested = _focusSelection;
      _preferredX = null;
      _scheduleSync();
    }
  }

  void unregister(ScreenplayEditingRowState row) => _rows.remove(row);
  ScreenplayEditingRowState? rowAt(int index) =>
      _rows.where((row) => row.mounted && row.index == index).firstOrNull;

  void _rootFocusChanged() {
    if (_focus.hasPrimaryFocus && _initialEmptyFocus) {
      _initialEmptyFocus = false;
      return;
    }
    if (_focus.hasPrimaryFocus && controller.value.isNotEmpty) {
      _focusSelection();
    }
  }

  void _focusSelection() {
    _requestFocus = true;
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_scheduled || !mounted) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || controller.isComposing) {
        return;
      }
      for (final row in _rows.toList()) {
        row.synchronize();
      }
      if (_requestFocus) {
        if (controller.value.isEmpty) {
          _requestFocus = false;
          _focus.requestFocus();
        } else {
          final position = controller.positionAt(
            controller.selection.extentOffset,
          );
          final row = rowAt(position.index);
          if (row != null) {
            _requestFocus = false;
            widget.onFocusElement(position.index, position.offset > 0);
            row.focusAt(position.offset);
          }
        }
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _selectOffset(int offset, {required bool extend, bool? forward}) {
    final selection = controller.selection;
    controller.select(
      extend
          ? selection.copyWith(extentOffset: offset)
          : TextSelection.collapsed(
              offset: !selection.isCollapsed && forward != null
                  ? (forward ? selection.end : selection.start)
                  : offset,
            ),
    );
  }

  int _word(int offset, bool forward) {
    if (controller.value.isEmpty) {
      return 0;
    }
    final position = controller.positionAt(offset);
    final row = rowAt(position.index)?.editable;
    final text = controller.textOf(controller.value[position.index]);
    var search = forward ? position.offset : position.offset - 1;
    if (row != null) {
      while (search >= 0 && search < text.length) {
        final range = row.renderEditable.getWordBoundary(
          TextPosition(offset: search),
        );
        final boundary = forward ? range.end : range.start;
        final part = text.substring(range.start, range.end);
        if (boundary == 0 ||
            boundary == text.length ||
            !RegExp(r'^[\s\p{P}]*$', unicode: true).hasMatch(part)) {
          return controller.startOf(position.index) + boundary;
        }
        final next = forward ? boundary : boundary - 1;
        if (next == search) {
          break;
        }
        search = next;
      }
    }
    final nextIndex = position.index + (forward ? 1 : -1);
    if (nextIndex < 0) {
      return 0;
    }
    if (nextIndex >= controller.value.length) {
      return controller.source.length;
    }
    return controller.startOf(nextIndex) +
        (forward ? 0 : controller.textOf(controller.value[nextIndex]).length);
  }

  void _vertical(bool down, bool extend, {bool page = false}) {
    if (controller.value.isEmpty) {
      return;
    }
    final selection = controller.selection;
    if (!extend && !selection.isCollapsed && controller.crossesElements) {
      _selectOffset(down ? selection.end : selection.start, extend: false);
      return;
    }
    final position = controller.positionAt(selection.extentOffset);
    final row = rowAt(position.index);
    final editable = row?.editable;
    if (editable != null) {
      final render = editable.renderEditable;
      final caretPosition = TextPosition(
        offset: position.offset,
        affinity: selection.affinity,
      );
      final caret = render.getLocalRectForCaret(caretPosition);
      final point = render.localToGlobal(caret.centerLeft);
      _preferredX ??= point.dx;
      if (!page) {
        final movement = render.startVerticalCaretMovement(caretPosition);
        if (down ? movement.moveNext() : movement.movePrevious()) {
          _selectOffset(
            controller.startOf(position.index) + movement.current.offset,
            extend: extend,
          );
          return;
        }
      } else {
        final height =
            Scrollable.maybeOf(row!.context)?.position.viewportDimension ??
            MediaQuery.sizeOf(context).height;
        final targetY = point.dy + (down ? height : -height);
        final textRows = _rows.where((r) => r.editable != null).toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final target = (down ? textRows : textRows.reversed).firstWhere((r) {
          final box = r.editable!.renderEditable;
          final top = box.localToGlobal(Offset.zero).dy;
          return down ? top + box.size.height >= targetY : top <= targetY;
        }, orElse: () => down ? textRows.last : textRows.first);
        final next = target.editable!.renderEditable.getPositionForPoint(
          Offset(_preferredX!, targetY),
        );
        _selectOffset(
          controller.startOf(target.index) + next.offset,
          extend: extend,
        );
        return;
      }
    }
    var nextIndex = position.index + (down ? 1 : -1);
    while (nextIndex >= 0 &&
        nextIndex < controller.value.length &&
        controller.value[nextIndex].type == ScreenplayElementType.character) {
      nextIndex += down ? 1 : -1;
    }
    final target = rowAt(nextIndex)?.editable;
    if (target == null) {
      return;
    }
    final render = target.renderEditable;
    final edge = render.getLocalRectForCaret(
      TextPosition(offset: down ? 0 : target.widget.controller.text.length),
    );
    final point = render.localToGlobal(edge.centerLeft);
    final next = render.getPositionForPoint(
      Offset(_preferredX ?? point.dx, point.dy),
    );
    _selectOffset(controller.startOf(nextIndex) + next.offset, extend: extend);
  }

  Future<void> _copy({bool cut = false}) async {
    final text = controller.selectedText();
    if (text.isEmpty) {
      return;
    }
    if (cut) {
      await controller.replaceRange(
        controller.selection.start,
        controller.selection.end,
        '',
        beforeReplace: (text) => Clipboard.setData(ClipboardData(text: text)),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _paste() async {
    final editor = controller;
    final revision = editor.revision;
    final selection = editor.selection;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted &&
        identical(controller, editor) &&
        data?.text != null &&
        controller.revision == revision &&
        controller.selection == selection) {
      await controller.replaceSelection(data!.text!);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (controller.isComposing) {
      return KeyEventResult.skipRemainingHandlers;
    }
    final keyboard = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command = apple ? keyboard.isMetaPressed : keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    if (!keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        unawaited(controller.enter(soft: shift));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab && widget.onCycleType != null) {
        widget.onCycleType!(shift);
        return KeyEventResult.handled;
      }
    }
    if (command && !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.keyA && !shift) {
        _preferredX = null;
        controller.select(
          TextSelection(baseOffset: 0, extentOffset: controller.source.length),
        );
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX) &&
          !shift) {
        unawaited(_copy(cut: key == LogicalKeyboardKey.keyX));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV && !shift) {
        _preferredX = null;
        unawaited(_paste());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyZ ||
          (!apple && key == LogicalKeyboardKey.keyY)) {
        _preferredX = null;
        if (shift || key == LogicalKeyboardKey.keyY) {
          controller.redo();
        } else {
          controller.undo();
        }
        return KeyEventResult.handled;
      }
    }
    if (!apple &&
        ((key == LogicalKeyboardKey.insert &&
                (keyboard.isControlPressed || shift)) ||
            (key == LogicalKeyboardKey.delete &&
                shift &&
                !keyboard.isControlPressed))) {
      if (key == LogicalKeyboardKey.insert && keyboard.isControlPressed) {
        unawaited(_copy());
      } else if (key == LogicalKeyboardKey.insert) {
        unawaited(_paste());
      } else {
        unawaited(_copy(cut: true));
      }
      return KeyEventResult.handled;
    }
    final selection = controller.selection;
    if (!selection.isValid) {
      return KeyEventResult.ignored;
    }
    final left = key == LogicalKeyboardKey.arrowLeft;
    final right = key == LogicalKeyboardKey.arrowRight;
    final up = key == LogicalKeyboardKey.arrowUp;
    final down = key == LogicalKeyboardKey.arrowDown;
    final backward = key == LogicalKeyboardKey.backspace;
    final forwardDelete = key == LogicalKeyboardKey.delete;
    final home = key == LogicalKeyboardKey.home;
    final end = key == LogicalKeyboardKey.end;
    final wordModifier = apple
        ? keyboard.isAltPressed
        : keyboard.isControlPressed;
    if (apple &&
        !command &&
        !keyboard.isAltPressed &&
        !shift &&
        (home ||
            end ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown)) {
      final row = rowAt(controller.positionAt(selection.extentOffset).index);
      final position = Scrollable.maybeOf(row?.context ?? context)?.position;
      if (position != null) {
        final towardEnd = end || key == LogicalKeyboardKey.pageDown;
        final offset = home || end
            ? (towardEnd ? position.maxScrollExtent : position.minScrollExtent)
            : position.pixels +
                  (towardEnd ? 1 : -1) * position.viewportDimension;
        position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      return KeyEventResult.handled;
    }
    int? target;
    bool forward = right || down || forwardDelete || end;
    if ((apple && command && (up || down)) ||
        (!apple && command && (home || end))) {
      target = forward ? controller.source.length : 0;
    } else if ((apple &&
            command &&
            (left || right || backward || forwardDelete)) ||
        (!command && !keyboard.isAltPressed && (home || end))) {
      final position = controller.positionAt(selection.extentOffset);
      final editable = rowAt(position.index)?.editable;
      final line = editable?.renderEditable.getLineAtOffset(
        TextPosition(offset: position.offset, affinity: selection.affinity),
      );
      target = controller.value.isEmpty
          ? 0
          : controller.startOf(position.index) +
                (forward
                    ? line?.end ??
                          controller
                              .textOf(controller.value[position.index])
                              .length
                    : line?.start ?? 0);
    } else if (wordModifier && (left || right || backward || forwardDelete)) {
      target = _word(selection.extentOffset, forward);
    } else if (apple && wordModifier && (up || down)) {
      final position = controller.positionAt(selection.extentOffset);
      if (shift) {
        final boundary = ParagraphBoundary(
          controller.source.replaceAll(screenplayElementSeparator, '\n'),
        );
        target = down
            ? boundary.getTrailingTextBoundaryAt(selection.extentOffset) ??
                  controller.source.length
            : boundary.getLeadingTextBoundaryAt(selection.extentOffset - 1) ??
                  0;
      } else {
        final line = rowAt(position.index)?.editable?.renderEditable
            .getLineAtOffset(TextPosition(offset: position.offset));
        target =
            controller.startOf(position.index) +
            (down ? line?.end ?? position.offset : line?.start ?? 0);
      }
    } else if (!apple && command && (up || down)) {
      final position = controller.positionAt(selection.extentOffset);
      target = down
          ? controller.startOf(
              (position.index + 1).clamp(0, controller.value.length),
            )
          : controller.startOf(
              (position.index - 1).clamp(0, controller.value.length),
            );
    } else if (!command &&
        !keyboard.isAltPressed &&
        (left || right || backward || forwardDelete)) {
      final boundary = CharacterBoundary(controller.source);
      target = forward
          ? boundary.getTrailingTextBoundaryAt(selection.extentOffset) ??
                controller.source.length
          : boundary.getLeadingTextBoundaryAt(selection.extentOffset - 1) ?? 0;
    } else if (!command &&
        !keyboard.isAltPressed &&
        (up ||
            down ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown)) {
      _vertical(
        down || key == LogicalKeyboardKey.pageDown,
        shift,
        page:
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown,
      );
      return KeyEventResult.handled;
    }
    if (target == null) {
      return KeyEventResult.ignored;
    }
    _preferredX = null;
    if (backward || forwardDelete) {
      if (!selection.isCollapsed) {
        unawaited(controller.replaceSelection(''));
      } else if (target != selection.extentOffset) {
        final current = controller.positionAt(selection.extentOffset);
        final next = controller.positionAt(target);
        if (backward &&
            !command &&
            !wordModifier &&
            current.index != next.index &&
            controller.value[next.index].isHeading &&
            controller.value[current.index].text.isEmpty &&
            !controller.value[current.index].isObject) {
          // 场内首行是空行时退格不并场：后面还有正文就只删这一行、光标落到下一行
          // 行首；这是本场唯一一行，就按删除空场确认。只删空行不行 —— 标题不是
          // 输入框，焦点会被转给上一场，光标跳出本场。
          final after = current.index + 1;
          if (after < controller.value.length &&
              !controller.value[after].isHeading) {
            final caret = controller.startOf(current.index);
            controller.edit(
              [...controller.value]..removeAt(current.index),
              selectionAfter: TextSelection.collapsed(offset: caret),
            );
            controller.select(TextSelection.collapsed(offset: caret));
          } else {
            unawaited(
              controller.deleteEmptyScene(
                controller.value[next.index].sceneId!,
              ),
            );
          }
        } else if (backward &&
            !command &&
            !wordModifier &&
            current.index != next.index &&
            controller.value[next.index].isHeading) {
          unawaited(
            controller.removeSceneHeading(
              controller.value[next.index].sceneId!,
            ),
          );
        } else if (backward &&
            !command &&
            !wordModifier &&
            current.index != next.index &&
            controller.value[current.index].text.isEmpty &&
            !controller.value[current.index].isObject &&
            controller.value[next.index].type ==
                ScreenplayElementType.character) {
          controller.edit(
            [...controller.value]..removeAt(current.index),
            selectionAfter: TextSelection.collapsed(offset: target),
          );
          controller.select(TextSelection.collapsed(offset: target));
        } else if (!command &&
            !wordModifier &&
            current.index != next.index &&
            // 空行退格不在这里拦：跨类型只移光标会把空行留在原地，光标又落进
            // 上一行，再退一次吃的是上一行的字，空行从此删不掉。放行到下面的
            // replaceRange，与「空对白接在对白后」已有的删除路径一致。往后删
            // 不放行 —— 那会把下一行的文字吸进这个空行，类型反而更错。
            !(backward && controller.value[current.index].text.isEmpty) &&
            controller.value[current.index].type !=
                controller.value[next.index].type) {
          controller.select(TextSelection.collapsed(offset: target));
        } else {
          unawaited(
            controller.replaceRange(
              forward ? selection.extentOffset : target,
              forward ? target : selection.extentOffset,
              '',
            ),
          );
        }
      }
    } else {
      _selectOffset(target, extend: shift, forward: forward);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final title = context.t(LocaleKeys.commonDelete);
    final message =
        '${context.t(LocaleKeys.screenplayDeleteDialogueBlock)}\n'
        '${context.t(LocaleKeys.screenplayConfirmDelete)}';
    controller.confirmDelete = () => showConfirmDialog(
      context,
      title: title,
      message: message,
      variant: ConfirmDialogVariant.warning,
    );
    return TextFindReplaceScope(
      overlayInViewport: true,
      controller: controller.screenplay == null
          ? controller.document
          : controller.findDocument,
      replaceRanges: controller.screenplay == null
          ? null
          : (ranges, text) =>
                unawaited(controller.replaceFindRanges(ranges, text)),
      editorFocusNode: _focus,
      ensureRangeVisible: (range, {required focusEditor}) {
        final selection = controller.screenplay == null
            ? TextSelection(baseOffset: range.start, extentOffset: range.end)
            : controller.selectionForFind(range);
        if (focusEditor) {
          controller.select(selection);
          if (controller.value.isNotEmpty) {
            final node =
                controller.value[controller.positionAt(selection.start).index];
            if (node.isHeading) {
              controller.onFindHeading?.call(node.id!);
            }
          }
        } else {
          final position = controller.positionAt(selection.end);
          rowAt(position.index)?.reveal(position.offset);
        }
      },
      child: _EditingScope(
        state: this,
        child: Focus(
          focusNode: _focus,
          autofocus: controller.value.isEmpty,
          onKeyEvent: _handleKey,
          child: Listener(
            onPointerDown: _mouseDown,
            onPointerMove: _mouseMove,
            onPointerUp: _mouseEnd,
            onPointerCancel: _mouseEnd,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopMouseSelection();
    controller.document.removeListener(_scheduleSync);
    controller.onSelectionRequested = null;
    _focus.removeListener(_rootFocusChanged);
    _focus.dispose();
    super.dispose();
  }
}

class _EditingScope extends InheritedWidget {
  const _EditingScope({required this.state, required super.child});
  final ScreenplayEditingScopeState state;
  @override
  bool updateShouldNotify(_EditingScope oldWidget) => oldWidget.state != state;
}

/// 原生选区菜单与快捷键使用相同的整场剪贴板，避免跨元素剪切只复制当前输入框。
Widget screenplayContextMenuBuilder(
  BuildContext context,
  EditableTextState editable,
) {
  final scope = ScreenplayEditingScope.maybeOf(context);
  if (scope == null) {
    return AdaptiveTextSelectionToolbar.editableText(
      editableTextState: editable,
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editable.contextMenuAnchors,
    buttonItems: [
      for (final item in editable.contextMenuButtonItems)
        if (item.onPressed == null)
          item
        else
          switch (item.type) {
            ContextMenuButtonType.copy => item.copyWith(
              onPressed: () {
                editable.hideToolbar();
                unawaited(scope._copy());
              },
            ),
            ContextMenuButtonType.cut => item.copyWith(
              onPressed: () {
                editable.hideToolbar();
                unawaited(scope._copy(cut: true));
              },
            ),
            ContextMenuButtonType.paste => item.copyWith(
              onPressed: () {
                editable.hideToolbar();
                unawaited(scope._paste());
              },
            ),
            ContextMenuButtonType.selectAll => item.copyWith(
              onPressed: () {
                editable.hideToolbar();
                scope.controller.select(
                  TextSelection(
                    baseOffset: 0,
                    extentOffset: scope.controller.source.length,
                  ),
                );
              },
            ),
            _ => item,
          },
    ],
  );
}
