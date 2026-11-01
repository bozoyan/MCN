// 职责: Markdown 平台文本输入桥 — 用单一 DeltaTextInputClient 把键盘与 IME 变化原子写入全文编辑值
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_controller.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/utils/text_input_formatters.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/text-input-ime.md

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_block_controller.dart';

/// 整个虚拟化编辑器唯一的系统文本输入客户端。
///
/// 平台端可以保留一份远端快照用于应用 delta，但它从不成为业务状态源；每次
/// 变化都经过 formatter 后一次性写回 [MarkdownBlockController.value]。
class MarkdownTextInputClient with DeltaTextInputClient {
  MarkdownTextInputClient({
    required this._controller,
    required this._inputFormatters,
    required this._enabled,
  }) {
    _controller.addListener(_handleControllerChanged);
    _controller.focusNode.addListener(_handleFocusChanged);
  }

  final MarkdownBlockController _controller;
  List<TextInputFormatter> _inputFormatters;
  bool _enabled;
  GlobalKey? _editorKey;
  TextInputConnection? _connection;
  TextEditingValue? _remoteValue;
  int _remoteStart = 0;
  int _remoteEnd = 0;
  bool _applyingPlatformValue = false;
  bool _disposed = false;
  bool _postFrameOpenScheduled = false;

  void bindEditor(GlobalKey editorKey) {
    _editorKey = editorKey;
    if (_controller.focusNode.hasFocus) {
      _openConnection();
    }
  }

  void updateConfiguration({
    required List<TextInputFormatter> inputFormatters,
    required bool enabled,
  }) {
    _inputFormatters = inputFormatters;
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    if (_enabled && _controller.focusNode.hasFocus) {
      _openConnection();
    } else {
      _closeConnection();
    }
  }

  void ensureInput() {
    if (!_enabled || _disposed) {
      return;
    }
    if (!_controller.focusNode.hasFocus) {
      _controller.focusNode.requestFocus();
      return;
    }
    _openConnection();
  }

  void updateGeometry({required Rect caretRect}) {
    final connection = _connection;
    final renderObject = _editorKey?.currentContext?.findRenderObject();
    if (connection == null ||
        !connection.attached ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return;
    }
    connection.setEditableSizeAndTransform(
      renderObject.size,
      renderObject.getTransformTo(null),
    );
    connection.setCaretRect(caretRect);
    if (_controller.value.isComposingRangeValid) {
      connection.setComposingRect(caretRect);
    }
  }

  Future<void> copySelection() async {
    final selection = _controller.selection;
    if (selection.isCollapsed) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(_controller.value.text)),
    );
  }

  Future<void> cutSelection() async {
    if (!_enabled || _controller.selection.isCollapsed) {
      return;
    }
    await copySelection();
    _controller.replaceSelection('');
  }

  Future<void> paste() async {
    if (!_enabled || _controller.isComposing) {
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final oldValue = _controller.value;
    final selection = oldValue.selection;
    final candidate = TextEditingValue(
      text: oldValue.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    _applyGlobalFormattedValue(oldValue, candidate, mergeable: false);
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue get currentTextEditingValue {
    final remote = _remoteValue;
    if (remote != null) {
      return remote;
    }
    final window = _remoteWindowFor(_controller.value);
    _installRemoteWindow(window);
    return window.value;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (!_enabled || deltas.isEmpty) {
      return;
    }
    final oldRemote = currentTextEditingValue;
    var nextRemote = oldRemote;
    for (final delta in deltas) {
      // A delta is relative to the platform's previous value. A local edit
      // (for example a physical Backspace handled by Focus) may have already
      // advanced our remote window before a stale platform delta arrives.
      // Applying that delta to the new window would overwrite the local edit.
      if (delta.oldText != nextRemote.text) {
        _resyncPlatformFromController();
        return;
      }
      nextRemote = delta.apply(nextRemote);
    }
    _applyRemoteValue(oldRemote, nextRemote);
  }

  @override
  void updateEditingValue(TextEditingValue nextValue) {
    if (!_enabled) {
      return;
    }
    _applyRemoteValue(currentTextEditingValue, nextValue);
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline &&
        defaultTargetPlatform == TargetPlatform.android) {
      _controller.replaceSelection('\n', mergeable: false);
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {
    final intent = intentForMacOSSelector(selectorName);
    final primaryContext = primaryFocus?.context;
    if (intent != null && primaryContext != null) {
      // macOS sends these selectors as native editing commands. Flutter's
      // EditableText applies them even when a composing range exists; keeping
      // the controller guard here would turn them into silent no-ops until
      // focus is lost and composing is cleared.
      if (intent is DeleteCharacterIntent && _controller.isComposing) {
        if (intent.forward) {
          _controller.deleteForward(allowComposing: true);
        } else {
          _controller.deleteBackward(allowComposing: true);
        }
        return;
      }
      if (intent is ExtendSelectionByCharacterIntent &&
          _controller.isComposing) {
        _controller.moveHorizontally(
          forward: intent.forward,
          extend: !intent.collapseSelection,
          allowComposing: true,
        );
        return;
      }
      Actions.invoke(primaryContext, intent);
    }
  }

  @override
  bool onFocusReceived() {
    if (!_enabled) {
      return false;
    }
    _controller.focusNode.requestFocus();
    return true;
  }

  @override
  void connectionClosed() {
    _connection = null;
    _remoteValue = null;
  }

  void _applyRemoteValue(
    TextEditingValue oldRemote,
    TextEditingValue nextRemote,
  ) {
    final oldGlobal = _controller.value;
    final candidate = _mapRemoteToGlobal(oldGlobal, nextRemote);
    final formatted = _format(oldGlobal, candidate);
    final previousRemoteStart = _remoteStart;
    _applyingPlatformValue = true;
    _controller.applyUserValue(formatted);
    _applyingPlatformValue = false;
    final accepted = _controller.value;
    if (accepted == formatted && formatted == candidate) {
      _remoteStart = previousRemoteStart;
      _remoteEnd = previousRemoteStart + nextRemote.text.length;
      _remoteValue = nextRemote;
      return;
    }
    _syncRemoteFromController(sendToPlatform: true);
  }

  void _applyGlobalFormattedValue(
    TextEditingValue oldValue,
    TextEditingValue candidate, {
    bool mergeable = true,
  }) {
    final formatted = _format(oldValue, candidate);
    _applyingPlatformValue = true;
    _controller.applyUserValue(formatted, mergeable: mergeable);
    _applyingPlatformValue = false;
    _syncRemoteFromController(sendToPlatform: true);
  }

  TextEditingValue _format(
    TextEditingValue oldValue,
    TextEditingValue candidate,
  ) {
    var formatted = candidate;
    for (final formatter in _inputFormatters) {
      formatted = formatter.formatEditUpdate(oldValue, formatted);
    }
    return formatted;
  }

  TextEditingValue _mapRemoteToGlobal(
    TextEditingValue oldGlobal,
    TextEditingValue remote,
  ) {
    final nextText = oldGlobal.text.replaceRange(
      _remoteStart,
      _remoteEnd,
      remote.text,
    );
    final selection = TextSelection(
      baseOffset: _remoteStart + remote.selection.baseOffset,
      extentOffset: _remoteStart + remote.selection.extentOffset,
      affinity: remote.selection.affinity,
      isDirectional: remote.selection.isDirectional,
    );
    final composing = remote.composing.isValid
        ? TextRange(
            start: _remoteStart + remote.composing.start,
            end: _remoteStart + remote.composing.end,
          )
        : TextRange.empty;
    return TextEditingValue(
      text: nextText,
      selection: selection,
      composing: composing,
    );
  }

  void _handleControllerChanged() {
    if (_disposed || _applyingPlatformValue) {
      return;
    }
    _syncRemoteFromController(sendToPlatform: true);
  }

  void _handleFocusChanged() {
    if (_controller.focusNode.hasFocus && _enabled) {
      _openConnection();
    } else {
      _closeConnection();
    }
  }

  void _openConnection() {
    if (_disposed || !_enabled || !_controller.focusNode.hasFocus) {
      return;
    }
    final context = _editorKey?.currentContext;
    if (context == null) {
      if (!_postFrameOpenScheduled) {
        _postFrameOpenScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameOpenScheduled = false;
          _openConnection();
        });
      }
      return;
    }
    final existing = _connection;
    if (existing?.attached == true) {
      existing!.show();
      return;
    }
    final connection = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: View.maybeOf(context)?.viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableDeltaModel: true,
        enableInteractiveSelection: true,
        autocorrect: true,
        enableSuggestions: true,
        keyboardAppearance: Theme.of(context).brightness,
      ),
    );
    final window = _remoteWindowFor(_controller.value);
    _installRemoteWindow(window);
    connection.setEditingState(window.value);
    connection.show();
    _connection = connection;
  }

  void _closeConnection() {
    final connection = _connection;
    if (connection?.attached == true) {
      connection!.close();
    }
    _connection = null;
    _remoteValue = null;
    _remoteStart = 0;
    _remoteEnd = 0;
  }

  void _syncRemoteFromController({required bool sendToPlatform}) {
    final window = _remoteWindowFor(_controller.value);
    final previous = _remoteValue;
    _installRemoteWindow(window);
    if (sendToPlatform &&
        previous != window.value &&
        _connection?.attached == true) {
      _connection!.setEditingState(window.value);
    }
  }

  void _resyncPlatformFromController() {
    final window = _remoteWindowFor(_controller.value);
    _installRemoteWindow(window);
    if (_connection?.attached == true) {
      _connection!.setEditingState(window.value);
    }
  }

  _MarkdownRemoteWindow _remoteWindowFor(TextEditingValue global) {
    final document = _controller.document;
    final selection = global.selection;
    var globalStart = selection.start;
    var globalEnd = selection.end;
    if (global.composing.isValid) {
      globalStart = math.min(globalStart, global.composing.start);
      globalEnd = math.max(globalEnd, global.composing.end);
    }
    final startBlock = document.blockIndexAt(globalStart);
    final endBlock = document.blockIndexAt(globalEnd);
    final start = document[startBlock].start;
    final endBlockValue = document[endBlock];
    final visualEnd = endBlockValue.separatorEnd > endBlockValue.end
        ? endBlockValue.separatorEnd - 1
        : endBlockValue.separatorEnd;
    final end = math.max(globalEnd, visualEnd);
    final localSelection = TextSelection(
      baseOffset: global.selection.baseOffset - start,
      extentOffset: global.selection.extentOffset - start,
      affinity: global.selection.affinity,
      isDirectional: global.selection.isDirectional,
    );
    final localComposing = global.composing.isValid
        ? TextRange(
            start: global.composing.start - start,
            end: global.composing.end - start,
          )
        : TextRange.empty;
    return _MarkdownRemoteWindow(
      start: start,
      end: end,
      value: TextEditingValue(
        text: global.text.substring(start, end),
        selection: localSelection,
        composing: localComposing,
      ),
    );
  }

  void _installRemoteWindow(_MarkdownRemoteWindow window) {
    _remoteStart = window.start;
    _remoteEnd = window.end;
    _remoteValue = window.value;
  }

  void dispose() {
    _disposed = true;
    _controller.removeListener(_handleControllerChanged);
    _controller.focusNode.removeListener(_handleFocusChanged);
    _closeConnection();
  }
}

class _MarkdownRemoteWindow {
  const _MarkdownRemoteWindow({
    required this.start,
    required this.end,
    required this.value,
  });

  final int start;
  final int end;
  final TextEditingValue value;
}
