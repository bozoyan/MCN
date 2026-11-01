// 职责: Markdown 全文编辑状态 — 以唯一 TextEditingValue 原子维护正文、全文选区、IME 组合区与撤销栈
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_document.dart
//   lib/shared/widgets/md/block/markdown_edit_patch_stack.dart
//   lib/shared/widgets/md/block/markdown_text_input_client.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/text-input-ime.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_block_document.dart';
import 'markdown_edit_patch_stack.dart';

/// Markdown 编辑器的唯一逻辑状态控制器。
///
/// [externalController] 的 [TextEditingValue] 同时承载全文、全局 selection 与
/// composing。块文档只是由全文派生的虚拟化索引，不再拥有独立编辑值。
class MarkdownBlockController extends ChangeNotifier {
  MarkdownBlockController({
    required TextEditingController externalController,
    required this._focusNode,
    this._undoController,
  }) : _externalController = externalController,
       _document = MarkdownBlockDocument.split(externalController.text),
       _lastExternalValue = externalController.value {
    _externalController.addListener(_handleExternalChanged);
    _focusNode.addListener(_handleFocusChanged);
    _undoController?.onUndo.addListener(_handleUndoRequested);
    _undoController?.onRedo.addListener(_handleRedoRequested);
  }

  final TextEditingController _externalController;
  final FocusNode _focusNode;
  final UndoHistoryController? _undoController;
  final MarkdownEditPatchStack _history = MarkdownEditPatchStack();

  MarkdownBlockDocument _document;
  TextEditingValue _lastExternalValue;
  TextEditingValue? _compositionBaseline;
  bool _syncingExternal = false;
  bool _disposed = false;

  MarkdownBlockDocument get document => _document;

  TextEditingController get externalController => _externalController;

  FocusNode get focusNode => _focusNode;

  /// 供平台输入客户端使用的合法全文编辑值。
  TextEditingValue get value => _normalizeValue(_externalController.value);

  TextSelection get selection => value.selection;

  int get activeBlockIndex => _document.blockIndexAt(selection.extentOffset);

  int get activeBlockId => _document[activeBlockIndex].id;

  bool get isComposing => value.isComposingRangeValid;

  bool get canUndo => _history.canUndo;

  bool get canRedo => _history.canRedo;

  String blockText(int index) => _document[index].textIn(_document.source);

  /// 把点击的块内位置转换为全文光标，并交给唯一 selection。
  void activateBlock(
    int blockIndex,
    int localOffset, {
    bool requestFocus = true,
  }) {
    if (_disposed) {
      return;
    }
    final safeIndex = blockIndex.clamp(0, _document.length - 1);
    final block = _document[safeIndex];
    final visualEnd = block.separatorEnd > block.end
        ? block.separatorEnd - 1
        : block.separatorEnd;
    final safeLocal = localOffset.clamp(0, visualEnd - block.start);
    setSelection(
      TextSelection.collapsed(offset: block.start + safeLocal),
      requestFocus: requestFocus,
    );
  }

  /// 激活全文范围。跨块范围与块内范围使用完全相同的全局 selection。
  void activateRange(TextRange range, {bool requestFocus = true}) {
    if (_disposed || !range.isValid) {
      return;
    }
    final safeStart = range.start.clamp(0, _document.source.length);
    final safeEnd = range.end.clamp(safeStart, _document.source.length);
    setSelection(
      TextSelection(baseOffset: safeStart, extentOffset: safeEnd),
      requestFocus: requestFocus,
    );
  }

  /// 原子更新全文 selection，并结束旧位置上的 IME composing。
  void setSelection(TextSelection nextSelection, {bool requestFocus = true}) {
    if (_disposed) {
      return;
    }
    final textLength = _document.source.length;
    final safeSelection = TextSelection(
      baseOffset: nextSelection.baseOffset.clamp(0, textLength),
      extentOffset: nextSelection.extentOffset.clamp(0, textLength),
      affinity: nextSelection.affinity,
      isDirectional: nextSelection.isDirectional,
    );
    applyUserValue(
      value.copyWith(selection: safeSelection, composing: TextRange.empty),
      mergeable: false,
    );
    if (requestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  /// 平台输入、粘贴和键盘命令的统一写入口。
  ///
  /// 文本、selection 与 composing 在一次赋值中发布。IME 草稿实时派生块视图，
  /// 但只在 composing 提交后记录一条撤销 patch。
  void applyUserValue(TextEditingValue nextValue, {bool mergeable = true}) {
    if (_disposed) {
      return;
    }
    final previous = value;
    final next = _normalizeValue(nextValue);
    if (previous == next) {
      return;
    }

    if (next.isComposingRangeValid) {
      _compositionBaseline ??= previous;
    } else {
      final historyBase = _compositionBaseline ?? previous;
      _compositionBaseline = null;
      _recordDiff(historyBase, next, mergeable: mergeable);
    }

    _document = _replaceDocumentByDiff(_document, next.text);
    _setExternalValue(next);
    _syncUndoController();
    notifyListeners();
  }

  /// 全文范围替换入口，供工具栏、删除、粘贴和查找替换复用。
  void replaceRange(
    int start,
    int end,
    String replacement, {
    required int selectionAfter,
    bool mergeable = false,
    bool allowComposing = false,
  }) {
    if (_disposed || (isComposing && !allowComposing)) {
      return;
    }
    final safeStart = start.clamp(0, _document.source.length);
    final safeEnd = end.clamp(safeStart, _document.source.length);
    final safeSelectionAfter = selectionAfter.clamp(
      0,
      _document.source.length - (safeEnd - safeStart) + replacement.length,
    );
    final before = value;
    final next = TextEditingValue(
      text: before.text.replaceRange(safeStart, safeEnd, replacement),
      selection: TextSelection.collapsed(offset: safeSelectionAfter),
    );
    _recordDiff(before, next, mergeable: mergeable);
    _compositionBaseline = null;
    _document = _document.replaceRange(safeStart, safeEnd, replacement);
    _setExternalValue(next);
    _syncUndoController();
    notifyListeners();
  }

  void replaceSelection(
    String replacement, {
    bool mergeable = false,
    bool allowComposing = false,
  }) {
    final currentSelection = selection;
    replaceRange(
      currentSelection.start,
      currentSelection.end,
      replacement,
      selectionAfter: currentSelection.start + replacement.length,
      mergeable: mergeable,
      allowComposing: allowComposing,
    );
  }

  void deleteBackward({bool allowComposing = false}) {
    if (isComposing && !allowComposing) {
      return;
    }
    final currentSelection = selection;
    if (!currentSelection.isCollapsed) {
      replaceSelection('', allowComposing: allowComposing);
      return;
    }
    final offset = currentSelection.extentOffset;
    if (offset <= 0) {
      return;
    }
    final start =
        CharacterBoundary(
          _document.source,
        ).getLeadingTextBoundaryAt(offset - 1) ??
        offset - 1;
    replaceRange(
      start,
      offset,
      '',
      selectionAfter: start,
      mergeable: true,
      allowComposing: allowComposing,
    );
  }

  void deleteForward({bool allowComposing = false}) {
    if (isComposing && !allowComposing) {
      return;
    }
    final currentSelection = selection;
    if (!currentSelection.isCollapsed) {
      replaceSelection('', allowComposing: allowComposing);
      return;
    }
    final offset = currentSelection.extentOffset;
    if (offset >= _document.source.length) {
      return;
    }
    final end = CharacterBoundary(
      _document.source,
    ).getTrailingTextBoundaryAt(offset);
    if (end == null) {
      return;
    }
    replaceRange(
      offset,
      end,
      '',
      selectionAfter: offset,
      mergeable: true,
      allowComposing: allowComposing,
    );
  }

  void moveHorizontally({
    required bool forward,
    required bool extend,
    bool allowComposing = false,
  }) {
    if (isComposing && !allowComposing) {
      return;
    }
    final current = selection;
    if (!extend && !current.isCollapsed) {
      setSelection(
        TextSelection.collapsed(offset: forward ? current.end : current.start),
        requestFocus: false,
      );
      return;
    }
    final extent = current.extentOffset;
    final boundary = CharacterBoundary(_document.source);
    final nextExtent = forward
        ? boundary.getTrailingTextBoundaryAt(extent) ?? _document.source.length
        : boundary.getLeadingTextBoundaryAt(extent - 1) ?? 0;
    setSelection(
      extend
          ? current.copyWith(extentOffset: nextExtent)
          : TextSelection.collapsed(offset: nextExtent),
      requestFocus: false,
    );
  }

  void selectAll() {
    setSelection(
      TextSelection(baseOffset: 0, extentOffset: _document.source.length),
      requestFocus: false,
    );
  }

  void undo() {
    if (isComposing) {
      return;
    }
    final outcome = _history.undo(_document.source);
    if (outcome == null) {
      _syncUndoController();
      return;
    }
    _applyHistoryOutcome(outcome);
  }

  void redo() {
    if (isComposing) {
      return;
    }
    final outcome = _history.redo(_document.source);
    if (outcome == null) {
      _syncUndoController();
      return;
    }
    _applyHistoryOutcome(outcome);
  }

  void _handleExternalChanged() {
    if (_syncingExternal || _disposed) {
      return;
    }
    final previous = _normalizeValue(_lastExternalValue);
    final next = _normalizeValue(_externalController.value);
    _lastExternalValue = _externalController.value;
    _compositionBaseline = null;
    _recordDiff(previous, next, mergeable: false);
    _document = _replaceDocumentByDiff(_document, next.text);
    _syncUndoController();
    notifyListeners();
  }

  void _handleFocusChanged() {
    if (_disposed) {
      return;
    }
    if (!_focusNode.hasFocus && isComposing) {
      applyUserValue(value.copyWith(composing: TextRange.empty));
    }
    _syncUndoController();
    notifyListeners();
  }

  void _handleUndoRequested() {
    if (_focusNode.hasFocus) {
      undo();
    }
  }

  void _handleRedoRequested() {
    if (_focusNode.hasFocus) {
      redo();
    }
  }

  void _recordDiff(
    TextEditingValue before,
    TextEditingValue after, {
    required bool mergeable,
  }) {
    final patch = _diffPatch(
      before: before.text,
      after: after.text,
      selectionBefore: before.selection.extentOffset,
      selectionAfter: after.selection.extentOffset,
    );
    if (patch != null) {
      _history.record(patch, mergeable: mergeable);
    }
  }

  void _applyHistoryOutcome(MarkdownEditOutcome outcome) {
    _compositionBaseline = null;
    _document = _replaceDocumentByDiff(_document, outcome.text);
    _setExternalValue(
      TextEditingValue(
        text: outcome.text,
        selection: TextSelection.collapsed(offset: outcome.selection),
      ),
    );
    _syncUndoController();
    notifyListeners();
  }

  void _setExternalValue(TextEditingValue next) {
    _syncingExternal = true;
    _externalController.value = next;
    _lastExternalValue = next;
    _syncingExternal = false;
  }

  void _syncUndoController() {
    if (!_focusNode.hasFocus) {
      return;
    }
    _undoController?.value = UndoHistoryValue(
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
    );
  }

  TextEditingValue _normalizeValue(TextEditingValue raw) {
    final textLength = raw.text.length;
    final selection = raw.selection.isValid
        ? TextSelection(
            baseOffset: raw.selection.baseOffset.clamp(0, textLength),
            extentOffset: raw.selection.extentOffset.clamp(0, textLength),
            affinity: raw.selection.affinity,
            isDirectional: raw.selection.isDirectional,
          )
        : TextSelection.collapsed(offset: textLength);
    final composing =
        raw.composing.isValid &&
            raw.composing.start >= 0 &&
            raw.composing.end <= textLength
        ? raw.composing
        : TextRange.empty;
    return TextEditingValue(
      text: raw.text,
      selection: selection,
      composing: composing,
    );
  }

  static MarkdownEditPatch? _diffPatch({
    required String before,
    required String after,
    required int selectionBefore,
    required int selectionAfter,
  }) {
    if (before == after) {
      return null;
    }
    var prefix = 0;
    final commonLength = before.length < after.length
        ? before.length
        : after.length;
    while (prefix < commonLength &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before.codeUnitAt(before.length - suffix - 1) ==
            after.codeUnitAt(after.length - suffix - 1)) {
      suffix++;
    }
    return MarkdownEditPatch(
      start: prefix,
      removed: before.substring(prefix, before.length - suffix),
      inserted: after.substring(prefix, after.length - suffix),
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
    );
  }

  static MarkdownBlockDocument _replaceDocumentByDiff(
    MarkdownBlockDocument document,
    String nextText,
  ) {
    if (document.source == nextText) {
      return document;
    }
    var prefix = 0;
    final commonLength = document.source.length < nextText.length
        ? document.source.length
        : nextText.length;
    while (prefix < commonLength &&
        document.source.codeUnitAt(prefix) == nextText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < document.source.length - prefix &&
        suffix < nextText.length - prefix &&
        document.source.codeUnitAt(document.source.length - suffix - 1) ==
            nextText.codeUnitAt(nextText.length - suffix - 1)) {
      suffix++;
    }
    return document.replaceRange(
      prefix,
      document.source.length - suffix,
      nextText.substring(prefix, nextText.length - suffix),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _externalController.removeListener(_handleExternalChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _undoController?.onUndo.removeListener(_handleUndoRequested);
    _undoController?.onRedo.removeListener(_handleRedoRequested);
    super.dispose();
  }
}
