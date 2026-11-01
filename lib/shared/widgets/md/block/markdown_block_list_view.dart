// 职责: Markdown 虚拟编辑视口 — 懒构建可见块并统一处理命中、选择、键盘、光标几何与最小滚动；触屏下提供长按选词、可拖动选择手柄与浮动操作菜单，空白处短按/长按弹出粘贴与换行；桌面下右键弹出剪切/复制/粘贴/全选菜单
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_controller.dart
//   lib/shared/widgets/md/block/markdown_block_metrics.dart
//   lib/shared/widgets/md/block/markdown_readonly_block.dart
//   lib/shared/widgets/md/block/markdown_text_input_client.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
//   .agents/rules/text-input-ime.md

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        LongPressGestureRecognizer,
        TapAndPanGestureRecognizer,
        TapGestureRecognizer,
        TapDragDownDetails,
        TapDragEndDetails,
        TapDragStartDetails,
        TapDragUpdateDetails,
        TapDragUpDetails,
        kDoubleTapSlop,
        kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/reveric_context_menu.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';
import 'markdown_block_controller.dart';
import 'markdown_block_metrics.dart';
import 'markdown_block_style.dart';
import 'markdown_readonly_block.dart';
import 'markdown_text_input_client.dart';

const Set<PointerDeviceKind> _desktopSelectionDevices = <PointerDeviceKind>{
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};
const Set<PointerDeviceKind> _touchSelectionDevices = <PointerDeviceKind>{
  PointerDeviceKind.touch,
};

/// 触屏选择手柄的命中边长（移动端触控目标 ≥44pt）与圆点半径。
const double _touchHandleHitSize = 44;
const double _touchHandleCircleRadius = 7;
const double _touchHandleGap = 2;

/// 触屏浮动菜单的估算尺寸，用于定位时水平夹取与上方放不下时翻转到选区下方。
const double _touchMenuHeight = 40;
const double _touchMenuHalfWidth = 170;
const double _touchCaretMenuHalfWidth = 90;

class MarkdownBlockListView extends StatefulWidget {
  const MarkdownBlockListView({
    super.key,
    required this.controller,
    required this.style,
    required this.enabled,
    required this.inputFormatters,
    required this.hintText,
    this.autoHeight = false,
  });

  final MarkdownBlockController controller;
  final MarkdownBlockStyle style;
  final bool enabled;
  final List<TextInputFormatter> inputFormatters;
  final String hintText;

  /// 随内容自增高：block 列表不再自己滚动，改由外层滚动容器承载。
  /// 代价是关闭虚拟化（所有 block 都会 layout），只用于短文字段。
  final bool autoHeight;

  @override
  State<MarkdownBlockListView> createState() => MarkdownBlockListViewState();
}

class MarkdownBlockListViewState extends State<MarkdownBlockListView> {
  final ScrollController _scrollController = ScrollController();
  final MarkdownBlockMetrics _metrics = MarkdownBlockMetrics();
  final Map<int, GlobalKey<MarkdownReadonlyBlockState>> _blockKeys =
      <int, GlobalKey<MarkdownReadonlyBlockState>>{};
  final GlobalKey _editorKey = GlobalKey();

  late MarkdownTextInputClient _inputClient;
  late final Map<ShortcutActivator, Intent> _additionalTextShortcuts;
  late final Map<Type, Action<Intent>> _textActions;
  int _ensureGeneration = 0;
  int? _selectionAnchor;
  Offset? _dragPosition;
  Timer? _dragScrollTimer;
  double? _preferredCursorX;
  TextSelection? _scheduledSelection;
  final Set<LogicalKeyboardKey> _handledKeysDown = <LogicalKeyboardKey>{};

  /// 手柄拖动时手指与文本锚点（caret 底部中心）的固定偏移；普通拖选为零。
  Offset _dragTextShift = Offset.zero;

  /// 长按选词命中的词范围；拖动越过词边界后按方向改锚定词首/词尾。
  TextRange? _longPressWordRange;

  /// 最近一次选择交互是否来自触屏；决定是否为当前选区绘制手柄与浮动菜单。
  bool _touchSelectionMode = false;

  /// 手柄拖动进行中：隐藏浮动菜单，避免它跟着选区跳动。
  bool _handleDragInProgress = false;

  /// 点过「复制」后为该选区隐藏菜单，选区变化后恢复。
  TextSelection? _menuHiddenFor;

  /// 手动双击判定用的上一次触屏点击时间与位置。
  DateTime? _lastTouchTapTime;
  Offset? _lastTouchTapPosition;

  @override
  void initState() {
    super.initState();
    _additionalTextShortcuts = _buildAdditionalTextShortcuts();
    _textActions = _buildTextActions();
    _inputClient = MarkdownTextInputClient(
      controller: widget.controller,
      inputFormatters: widget.inputFormatters,
      enabled: widget.enabled,
    )..bindEditor(_editorKey);
    _scrollController.addListener(_handleScrollForTouchOverlays);
  }

  @override
  void didUpdateWidget(covariant MarkdownBlockListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _inputClient.dispose();
      _inputClient = MarkdownTextInputClient(
        controller: widget.controller,
        inputFormatters: widget.inputFormatters,
        enabled: widget.enabled,
      )..bindEditor(_editorKey);
      _blockKeys.clear();
      _scheduledSelection = null;
      _touchSelectionMode = false;
      _handleDragInProgress = false;
      _menuHiddenFor = null;
      _longPressWordRange = null;
      _dragTextShift = Offset.zero;
    }
    _inputClient.updateConfiguration(
      inputFormatters: widget.inputFormatters,
      enabled: widget.enabled,
    );
    final ids = widget.controller.document.blocks
        .map((block) => block.id)
        .toSet();
    _blockKeys.removeWhere((id, _) => !ids.contains(id));
    _metrics.retainOnly(ids);
  }

  @override
  void dispose() {
    _stopDragAutoScroll();
    _inputClient.dispose();
    _scrollController.removeListener(_handleScrollForTouchOverlays);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _touchSelectionActive {
    return widget.enabled && _touchSelectionMode;
  }

  /// 把全文范围起点所在块滚进视口；未挂载目标先估算，再用实际几何校正。
  Future<void> ensureRangeVisible(TextRange range) async {
    if (!mounted || !range.isValid) {
      return;
    }
    final document = widget.controller.document;
    final blockIndex = document.blockIndexAt(range.start);
    final generation = ++_ensureGeneration;
    await _ensureBlockVisible(blockIndex, generation, 0);
  }

  Future<void> _ensureBlockVisible(
    int blockIndex,
    int generation,
    int attempt,
  ) async {
    if (!mounted || generation != _ensureGeneration) {
      return;
    }
    final document = widget.controller.document;
    final safeIndex = blockIndex.clamp(0, document.length - 1);
    final targetContext = _blockKeys[document[safeIndex].id]?.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.15,
        duration: Duration.zero,
      );
      _captureMountedMetrics();
      return;
    }
    if (!_scrollController.hasClients || attempt >= 3) {
      return;
    }

    _captureMountedMetrics();
    final estimatedTarget =
        RevericSpacing.x3l + _metrics.estimatedOffsetOf(document, safeIndex);
    final calibratedTarget = _calibratedOffset(safeIndex, estimatedTarget);
    final position = _scrollController.position;
    _scrollController.jumpTo(
      calibratedTarget.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await _ensureBlockVisible(safeIndex, generation, attempt + 1);
  }

  double _calibratedOffset(int targetIndex, double fallback) {
    final viewport = _editorRenderBox;
    if (viewport == null || !viewport.attached) {
      return fallback;
    }
    int? nearestIndex;
    Rect? nearestRect;
    var nearestDistance = 1 << 30;
    final document = widget.controller.document;
    for (var index = 0; index < document.length; index++) {
      final rect = _stateForIndex(index)?.paragraphGlobalRect;
      if (rect == null) {
        continue;
      }
      final distance = (index - targetIndex).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
        nearestRect = rect;
      }
    }
    if (nearestIndex == null || nearestRect == null) {
      return fallback;
    }
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final actualNearestOffset =
        _scrollController.offset + nearestRect.top - viewportTop;
    final estimatedDelta =
        _metrics.estimatedOffsetOf(document, targetIndex) -
        _metrics.estimatedOffsetOf(document, nearestIndex);
    return actualNearestOffset + estimatedDelta;
  }

  void _captureMountedMetrics() {
    for (final block in widget.controller.document.blocks) {
      final state = _blockKeys[block.id]?.currentState;
      final rect = state?.paragraphGlobalRect;
      final context = _blockKeys[block.id]?.currentContext;
      final box = context?.findRenderObject();
      if (rect != null && box is RenderBox && box.attached) {
        _metrics.recordMeasured(block.id, box.size.height);
      }
    }
  }

  GlobalKey<MarkdownReadonlyBlockState> _keyFor(int blockId) {
    return _blockKeys.putIfAbsent(
      blockId,
      GlobalKey<MarkdownReadonlyBlockState>.new,
    );
  }

  MarkdownReadonlyBlockState? _stateForIndex(int index) {
    final document = widget.controller.document;
    if (index < 0 || index >= document.length) {
      return null;
    }
    return _blockKeys[document[index].id]?.currentState;
  }

  RenderBox? get _editorRenderBox {
    final renderObject = _editorKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  Rect? get _editorGlobalRect {
    final box = _editorRenderBox;
    if (box == null || !box.attached) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  ({MarkdownReadonlyBlockState state, TextPosition position})?
  _textHitForGlobalPosition(Offset position) {
    MarkdownReadonlyBlockState? nearest;
    var nearestDistance = double.infinity;
    for (final key in _blockKeys.values) {
      final state = key.currentState;
      final rect = state?.paragraphGlobalRect;
      if (state == null || rect == null) {
        continue;
      }
      if (position.dy >= rect.top && position.dy <= rect.bottom) {
        return (
          state: state,
          position: state.globalTextPositionForPosition(position),
        );
      }
      final distance = position.dy < rect.top
          ? rect.top - position.dy
          : position.dy - rect.bottom;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = state;
      }
    }
    return nearest == null
        ? null
        : (
            state: nearest,
            position: nearest.globalTextPositionForPosition(position),
          );
  }

  TextPosition? _textPositionForGlobalPosition(Offset position) {
    return _textHitForGlobalPosition(position)?.position;
  }

  /// 点在空字段，或点在正文矩形之外的编辑器留白（如自增高 minHeight 空档）。
  bool _isTouchEmptySpace(Offset globalPosition) {
    if (widget.controller.document.source.isEmpty) {
      return true;
    }
    final editorRect = _editorGlobalRect;
    if (editorRect == null || !editorRect.contains(globalPosition)) {
      return false;
    }
    for (final key in _blockKeys.values) {
      final rect = key.currentState?.paragraphGlobalRect;
      if (rect != null && rect.contains(globalPosition)) {
        return false;
      }
    }
    return true;
  }

  bool get _shiftPressed => HardwareKeyboard.instance.logicalKeysPressed.any(
    <LogicalKeyboardKey>{
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    }.contains,
  );

  int _effectiveConsecutiveTapCount(int rawCount) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux =>
        rawCount <= 3 ? rawCount : (rawCount % 3 == 0 ? 3 : rawCount % 3),
      TargetPlatform.iOS || TargetPlatform.macOS => math.min(rawCount, 3),
      TargetPlatform.windows => rawCount < 2 ? rawCount : 2 + rawCount % 2,
    };
  }

  void _handleDesktopTapDown(TapDragDownDetails details) {
    _touchSelectionMode = false;
    switch (_effectiveConsecutiveTapCount(details.consecutiveTapCount)) {
      case 2:
        _selectWordAt(details.globalPosition);
      case 3:
        _selectParagraphAt(details.globalPosition);
    }
  }

  void _handleDesktopTapUp(TapDragUpDetails details) {
    if (_effectiveConsecutiveTapCount(details.consecutiveTapCount) != 1) {
      return;
    }
    _handleDesktopSingleTap(details.globalPosition);
  }

  void _handleDesktopSingleTap(Offset globalPosition) {
    if (!widget.enabled) {
      return;
    }
    _touchSelectionMode = false;
    final position = _textPositionForGlobalPosition(globalPosition);
    if (position == null) {
      return;
    }
    _inputClient.ensureInput();
    final anchor = _shiftPressed
        ? widget.controller.selection.baseOffset
        : position.offset;
    _preferredCursorX = null;
    widget.controller.setSelection(
      TextSelection(
        baseOffset: anchor,
        extentOffset: position.offset,
        affinity: position.affinity,
      ),
    );
  }

  /// 桌面右键：点在选区内保留选区，点在选区外先把光标移过去，再弹出上下文菜单。
  void _handleSecondaryTapDown(TapDownDetails details) {
    if (!widget.enabled) {
      return;
    }
    _touchSelectionMode = false;
    final selection = widget.controller.selection;
    final position = _textPositionForGlobalPosition(details.globalPosition);
    final insideSelection =
        !selection.isCollapsed &&
        position != null &&
        position.offset >= selection.start &&
        position.offset <= selection.end;
    _inputClient.ensureInput();
    if (!insideSelection && position != null) {
      _preferredCursorX = null;
      widget.controller.setSelection(TextSelection.fromPosition(position));
    }
    unawaited(_showDesktopContextMenu(details.globalPosition));
  }

  Future<void> _showDesktopContextMenu(Offset globalPosition) async {
    // 剪贴板为空时粘贴置灰，避免点了没反应。
    final canPaste = await Clipboard.hasStrings();
    if (!mounted) {
      return;
    }
    final hasSelection = !widget.controller.selection.isCollapsed;
    final hasContent = widget.controller.document.source.isNotEmpty;
    await showRevericContextMenu(
      context: context,
      position: globalPosition,
      minWidth: 160,
      entries: <RevericMenuEntry>[
        RevericMenuItem(
          label: context.t(LocaleKeys.commonCut),
          enabled: hasSelection,
          onTap: hasSelection
              ? () => unawaited(_inputClient.cutSelection())
              : null,
        ),
        // 图标集里没有剪切/粘贴，四项统一不带图标，避免只有复制一项缩进。
        RevericMenuItem(
          label: context.t(LocaleKeys.commonCopy),
          enabled: hasSelection,
          onTap: hasSelection
              ? () => unawaited(_inputClient.copySelection())
              : null,
        ),
        RevericMenuItem(
          label: context.t(LocaleKeys.commonPaste),
          enabled: canPaste,
          onTap: canPaste ? () => unawaited(_inputClient.paste()) : null,
        ),
        const RevericMenuDivider(),
        RevericMenuItem(
          label: context.t(LocaleKeys.commonSelectAll),
          enabled: hasContent,
          onTap: hasContent ? _handleMenuSelectAll : null,
        ),
      ],
    );
  }

  void _selectWordAt(Offset globalPosition) {
    if (!widget.enabled) {
      return;
    }
    final hit = _textHitForGlobalPosition(globalPosition);
    final range = hit?.state.globalWordRangeAt(hit.position);
    if (range == null) {
      return;
    }
    _inputClient.ensureInput();
    _preferredCursorX = null;
    widget.controller.activateRange(range);
  }

  void _selectParagraphAt(Offset globalPosition) {
    if (!widget.enabled) {
      return;
    }
    final position = _textPositionForGlobalPosition(globalPosition);
    if (position == null) {
      return;
    }
    final source = widget.controller.document.source;
    final boundary = ParagraphBoundary(source);
    final leadingProbe =
        position.offset == source.length ||
            position.affinity == TextAffinity.upstream
        ? position.offset - 1
        : position.offset;
    final range = TextRange(
      start: boundary.getLeadingTextBoundaryAt(leadingProbe) ?? 0,
      end: boundary.getTrailingTextBoundaryAt(position.offset) ?? source.length,
    );
    _inputClient.ensureInput();
    _preferredCursorX = null;
    widget.controller.activateRange(range);
  }

  void _handleSelectionDragStart(TapDragStartDetails details) {
    if (!widget.enabled) {
      return;
    }
    _touchSelectionMode = false;
    final position = _textPositionForGlobalPosition(details.globalPosition);
    if (position == null) {
      return;
    }
    _inputClient.ensureInput();
    _dragPosition = details.globalPosition;
    _selectionAnchor = _shiftPressed
        ? widget.controller.selection.baseOffset
        : position.offset;
    _preferredCursorX = null;
    widget.controller.setSelection(
      TextSelection(
        baseOffset: _selectionAnchor!,
        extentOffset: position.offset,
        affinity: position.affinity,
      ),
    );
  }

  void _handleSelectionDragUpdate(TapDragUpdateDetails details) {
    if (_selectionAnchor == null) {
      return;
    }
    _dragPosition = details.globalPosition;
    _extendSelectionTo(details.globalPosition);
    _startDragAutoScrollIfNeeded();
  }

  void _handleSelectionDragEnd(TapDragEndDetails details) {
    _finishSelectionDrag();
  }

  void _finishSelectionDrag() {
    _selectionAnchor = null;
    _dragPosition = null;
    _dragTextShift = Offset.zero;
    _stopDragAutoScroll();
  }

  void _handleTouchTap(TapUpDetails details) {
    if (!widget.enabled || details.kind != PointerDeviceKind.touch) {
      return;
    }
    // 双击选词手动判定：框架的 DoubleTapGestureRecognizer 会 hold 住手势
    // 竞技场，把单击放置光标延迟到双击超时，这里按时间与位移阈值自行识别。
    final now = DateTime.now();
    final lastTime = _lastTouchTapTime;
    final lastPosition = _lastTouchTapPosition;
    _lastTouchTapTime = now;
    _lastTouchTapPosition = details.globalPosition;
    final isDoubleTap =
        lastTime != null &&
        lastPosition != null &&
        now.difference(lastTime) <= kDoubleTapTimeout &&
        (details.globalPosition - lastPosition).distance <= kDoubleTapSlop;
    if (isDoubleTap) {
      // 清空记录，避免三连击再次触发选词。
      _lastTouchTapTime = null;
      _lastTouchTapPosition = null;
      _touchSelectionMode = true;
      _menuHiddenFor = null;
      _selectWordAt(details.globalPosition);
      setState(() {});
      return;
    }
    final position = _textPositionForGlobalPosition(details.globalPosition);
    if (position == null) {
      return;
    }
    _menuHiddenFor = null;
    _preferredCursorX = null;
    final emptySpace = _isTouchEmptySpace(details.globalPosition);
    // 空白处再点一次收起粘贴/换行菜单；点在字上始终收起。
    _touchSelectionMode = emptySpace && !_touchSelectionMode;
    widget.controller.setSelection(TextSelection.fromPosition(position));
    _inputClient.ensureInput();
    setState(() {});
  }

  void _handleTouchLongPressStart(LongPressStartDetails details) {
    if (!widget.enabled) {
      return;
    }
    final hit = _textHitForGlobalPosition(details.globalPosition);
    if (hit == null) {
      final editorRect = _editorGlobalRect;
      if (editorRect == null || !editorRect.contains(details.globalPosition)) {
        return;
      }
      _touchSelectionMode = true;
      _menuHiddenFor = null;
      _preferredCursorX = null;
      _inputClient.ensureInput();
      final end = widget.controller.document.source.length;
      widget.controller.setSelection(TextSelection.collapsed(offset: end));
      _longPressWordRange = TextRange.collapsed(end);
      setState(() {});
      return;
    }
    _touchSelectionMode = true;
    _menuHiddenFor = null;
    _preferredCursorX = null;
    _inputClient.ensureInput();
    final range = hit.state.globalWordRangeAt(hit.position);
    if (range == null || range.isCollapsed) {
      // 空白处没有词：先放光标，松手后再出粘贴/换行菜单。
      widget.controller.setSelection(TextSelection.fromPosition(hit.position));
      _longPressWordRange = TextRange.collapsed(hit.position.offset);
      setState(() {});
      return;
    }
    _longPressWordRange = range;
    _selectionAnchor = range.start;
    _dragPosition = details.globalPosition;
    widget.controller.activateRange(range);
    setState(() {});
  }

  void _handleTouchLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final word = _longPressWordRange;
    if (word == null || word.isCollapsed) {
      return;
    }
    _dragPosition = details.globalPosition;
    final position = _textPositionForGlobalPosition(details.globalPosition);
    if (position == null) {
      return;
    }
    if (position.offset <= word.start) {
      _selectionAnchor = word.end;
    } else if (position.offset >= word.end) {
      _selectionAnchor = word.start;
    } else {
      // 回到词内：恢复整词选中。
      _selectionAnchor = word.start;
      widget.controller.setSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
        requestFocus: false,
      );
      return;
    }
    _extendSelectionTo(details.globalPosition);
    _startDragAutoScrollIfNeeded();
  }

  void _handleTouchLongPressEnd(LongPressEndDetails details) {
    _finishTouchLongPress();
  }

  void _handleTouchLongPressCancel() {
    _finishTouchLongPress();
  }

  void _finishTouchLongPress() {
    _longPressWordRange = null;
    _finishSelectionDrag();
    // 松手不改动选区，controller 不会触发重建，这里自行刷新出浮动菜单。
    if (mounted) {
      setState(() {});
    }
  }

  /// 拖动手柄时固定另一端，手指位置换算成文本锚点（保持按下时的抓取偏移）。
  void _handleSelectionHandleDragStart(bool isStart, DragStartDetails details) {
    if (!widget.enabled) {
      return;
    }
    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      return;
    }
    _touchSelectionMode = true;
    _menuHiddenFor = null;
    _handleDragInProgress = true;
    _preferredCursorX = null;
    _selectionAnchor = isStart ? selection.end : selection.start;
    final caretGlobal = _globalCaretRectForOffset(
      isStart ? selection.start : selection.end,
    );
    _dragTextShift = caretGlobal == null
        ? Offset.zero
        : caretGlobal.bottomCenter - details.globalPosition;
    _dragPosition = details.globalPosition;
    setState(() {});
  }

  void _handleSelectionHandleDragUpdate(DragUpdateDetails details) {
    if (_selectionAnchor == null) {
      return;
    }
    _dragPosition = details.globalPosition;
    _extendSelectionTo(details.globalPosition);
    _startDragAutoScrollIfNeeded();
  }

  void _handleSelectionHandleDragEnd(DragEndDetails details) {
    if (!_handleDragInProgress) {
      return;
    }
    _handleDragInProgress = false;
    _finishSelectionDrag();
    setState(() {});
  }

  void _handleMenuCopy() {
    unawaited(_inputClient.copySelection());
    setState(() {
      _menuHiddenFor = widget.controller.selection;
    });
  }

  void _handleMenuCut() {
    unawaited(_inputClient.cutSelection());
    _touchSelectionMode = false;
    _menuHiddenFor = null;
    setState(() {});
  }

  void _handleMenuPaste() {
    unawaited(_inputClient.paste());
    _touchSelectionMode = false;
    _menuHiddenFor = widget.controller.selection;
    setState(() {});
  }

  void _handleMenuNewline() {
    widget.controller.replaceSelection('\n');
    _touchSelectionMode = false;
    _menuHiddenFor = null;
    setState(() {});
  }

  void _handleMenuSelectAll() {
    _preferredCursorX = null;
    widget.controller.selectAll();
  }

  /// 触屏手柄与菜单的几何来自块渲染矩形，滚动时需要跟随重算。
  /// 仅在触屏选区存在时重建，避免普通滚动触发整树刷新。
  void _handleScrollForTouchOverlays() {
    if (!mounted || !_touchSelectionMode) {
      return;
    }
    setState(() {});
  }

  Rect? _globalCaretRectForOffset(int offset) {
    final document = widget.controller.document;
    if (document.length == 0) {
      return null;
    }
    final safeOffset = offset.clamp(0, document.source.length);
    return _stateForIndex(
      document.blockIndexAt(safeOffset),
    )?.globalCaretRect(safeOffset);
  }

  void _extendSelectionTo(Offset position) {
    final anchor = _selectionAnchor;
    final textPosition = _textPositionForGlobalPosition(
      position + _dragTextShift,
    );
    if (anchor == null || textPosition == null) {
      return;
    }
    widget.controller.setSelection(
      TextSelection(
        baseOffset: anchor,
        extentOffset: textPosition.offset,
        affinity: textPosition.affinity,
      ),
      requestFocus: false,
    );
  }

  void _startDragAutoScrollIfNeeded() {
    final position = _dragPosition;
    final viewport = _editorGlobalRect;
    if (position == null ||
        viewport == null ||
        position.dy >= viewport.top && position.dy <= viewport.bottom) {
      _stopDragAutoScroll();
      return;
    }
    _dragScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 32),
      (_) => _autoScrollSelection(),
    );
  }

  void _autoScrollSelection() {
    final position = _dragPosition;
    final viewport = _editorGlobalRect;
    if (!mounted ||
        position == null ||
        viewport == null ||
        !_scrollController.hasClients) {
      _stopDragAutoScroll();
      return;
    }
    final overflow = position.dy < viewport.top
        ? position.dy - viewport.top
        : position.dy > viewport.bottom
        ? position.dy - viewport.bottom
        : 0.0;
    if (overflow == 0) {
      _stopDragAutoScroll();
      return;
    }
    final scrollPosition = _scrollController.position;
    final delta = overflow.clamp(-48.0, 48.0);
    final next = (_scrollController.offset + delta).clamp(
      scrollPosition.minScrollExtent,
      scrollPosition.maxScrollExtent,
    );
    if (next == _scrollController.offset) {
      return;
    }
    _scrollController.jumpTo(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragPosition != null) {
        _extendSelectionTo(_dragPosition!);
      }
    });
  }

  void _stopDragAutoScroll() {
    _dragScrollTimer?.cancel();
    _dragScrollTimer = null;
  }

  Map<ShortcutActivator, Intent> _buildAdditionalTextShortcuts() {
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return const <ShortcutActivator, Intent>{};
    }
    return const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoTextIntent(
        SelectionChangedCause.keyboard,
      ),
      SingleActivator(
        LogicalKeyboardKey.arrowUp,
        control: true,
      ): ExtendSelectionToNextParagraphBoundaryIntent(
        forward: false,
        collapseSelection: true,
      ),
      SingleActivator(
        LogicalKeyboardKey.arrowDown,
        control: true,
      ): ExtendSelectionToNextParagraphBoundaryIntent(
        forward: true,
        collapseSelection: true,
      ),
    };
  }

  Map<Type, Action<Intent>> _buildTextActions() => <Type, Action<Intent>>{
    SelectAllTextIntent: _textAction<SelectAllTextIntent>(
      onInvoke: (_) {
        widget.controller.selectAll();
        _preferredCursorX = null;
        return null;
      },
    ),
    CopySelectionTextIntent: _textAction<CopySelectionTextIntent>(
      onInvoke: (intent) {
        if (intent.collapseSelection) {
          unawaited(_inputClient.cutSelection());
          _preferredCursorX = null;
        } else {
          unawaited(_inputClient.copySelection());
        }
        return null;
      },
    ),
    PasteTextIntent: _textAction<PasteTextIntent>(
      onInvoke: (_) {
        unawaited(_inputClient.paste());
        _preferredCursorX = null;
        return null;
      },
    ),
    UndoTextIntent: _textAction<UndoTextIntent>(
      onInvoke: (_) {
        widget.controller.undo();
        _preferredCursorX = null;
        return null;
      },
    ),
    RedoTextIntent: _textAction<RedoTextIntent>(
      onInvoke: (_) {
        widget.controller.redo();
        _preferredCursorX = null;
        return null;
      },
    ),
    DeleteCharacterIntent: _textAction<DeleteCharacterIntent>(
      onInvoke: (intent) {
        if (intent.forward) {
          widget.controller.deleteForward();
        } else {
          widget.controller.deleteBackward();
        }
        _preferredCursorX = null;
        return null;
      },
    ),
    DeleteToNextWordBoundaryIntent: _textAction<DeleteToNextWordBoundaryIntent>(
      onInvoke: (intent) {
        _deleteToBoundary(
          (position) => _wordBoundaryTarget(position, forward: intent.forward),
        );
        return null;
      },
    ),
    DeleteToLineBreakIntent: _textAction<DeleteToLineBreakIntent>(
      onInvoke: (intent) {
        _deleteToBoundary(
          (position) => _lineBoundaryTarget(position, forward: intent.forward),
        );
        return null;
      },
    ),
    ExtendSelectionByCharacterIntent:
        _textAction<ExtendSelectionByCharacterIntent>(
          onInvoke: (intent) {
            widget.controller.moveHorizontally(
              forward: intent.forward,
              extend: !intent.collapseSelection,
            );
            _preferredCursorX = null;
            return null;
          },
        ),
    ExtendSelectionVerticallyToAdjacentLineIntent:
        _textAction<ExtendSelectionVerticallyToAdjacentLineIntent>(
          onInvoke: (intent) {
            _moveVertically(
              upward: !intent.forward,
              extend: !intent.collapseSelection,
            );
            return null;
          },
        ),
    ExtendSelectionToNextWordBoundaryIntent:
        _textAction<ExtendSelectionToNextWordBoundaryIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _wordBoundaryTarget(position, forward: intent.forward),
            );
            return null;
          },
        ),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
        _textAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _wordBoundaryTarget(position, forward: intent.forward),
            );
            return null;
          },
        ),
    ExtendSelectionToLineBreakIntent:
        _textAction<ExtendSelectionToLineBreakIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _lineBoundaryTarget(position, forward: intent.forward),
            );
            return null;
          },
        ),
    ExpandSelectionToLineBreakIntent:
        _textAction<ExpandSelectionToLineBreakIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _lineBoundaryTarget(position, forward: intent.forward),
              expand: true,
            );
            return null;
          },
        ),
    ExtendSelectionToDocumentBoundaryIntent:
        _textAction<ExtendSelectionToDocumentBoundaryIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (_) => TextPosition(
                offset: intent.forward
                    ? widget.controller.value.text.length
                    : 0,
              ),
            );
            return null;
          },
        ),
    ExpandSelectionToDocumentBoundaryIntent:
        _textAction<ExpandSelectionToDocumentBoundaryIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (_) => TextPosition(
                offset: intent.forward
                    ? widget.controller.value.text.length
                    : 0,
              ),
              expand: true,
            );
            return null;
          },
        ),
    ExtendSelectionToNextParagraphBoundaryIntent:
        _textAction<ExtendSelectionToNextParagraphBoundaryIntent>(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _paragraphBoundaryTarget(position, forward: intent.forward),
            );
            return null;
          },
        ),
    ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent:
        _textAction<
          ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent
        >(
          onInvoke: (intent) {
            _moveSelectionToBoundary(
              intent,
              (position) =>
                  _paragraphBoundaryTarget(position, forward: intent.forward),
            );
            return null;
          },
        ),
    ScrollToDocumentBoundaryIntent: _textAction<ScrollToDocumentBoundaryIntent>(
      onInvoke: (intent) {
        if (_scrollController.hasClients) {
          final position = _scrollController.position;
          _scrollController.jumpTo(
            intent.forward
                ? position.maxScrollExtent
                : position.minScrollExtent,
          );
        }
        return null;
      },
    ),
  };

  Action<T> _textAction<T extends Intent>({
    required Object? Function(T intent) onInvoke,
  }) {
    return _ComposingAwareCallbackAction<T>(
      isEnabled: () => widget.enabled && !widget.controller.isComposing,
      onInvoke: onInvoke,
    );
  }

  void _deleteToBoundary(
    TextPosition Function(TextPosition position) targetFor,
  ) {
    if (!widget.enabled || widget.controller.isComposing) {
      return;
    }
    final selection = widget.controller.selection;
    if (!selection.isCollapsed) {
      widget.controller.replaceSelection('');
      _preferredCursorX = null;
      return;
    }
    final target = targetFor(selection.extent).offset;
    if (target == selection.extentOffset) {
      return;
    }
    final start = math.min(target, selection.extentOffset);
    final end = math.max(target, selection.extentOffset);
    widget.controller.replaceRange(
      start,
      end,
      '',
      selectionAfter: start,
      mergeable: true,
    );
    _preferredCursorX = null;
  }

  void _moveSelectionToBoundary(
    DirectionalCaretMovementIntent intent,
    TextPosition Function(TextPosition position) targetFor, {
    bool expand = false,
  }) {
    if (!widget.enabled || widget.controller.isComposing) {
      return;
    }
    final selection = widget.controller.selection;
    if (!selection.isCollapsed && intent.collapseSelection) {
      widget.controller.setSelection(
        TextSelection.collapsed(
          offset: intent.forward ? selection.end : selection.start,
        ),
        requestFocus: false,
      );
      _preferredCursorX = null;
      return;
    }
    final shouldTargetBase =
        expand &&
        (intent.forward
            ? selection.baseOffset > selection.extentOffset
            : selection.baseOffset < selection.extentOffset);
    final target = targetFor(
      shouldTargetBase ? selection.base : selection.extent,
    );
    final moved = intent.collapseSelection
        ? TextSelection.fromPosition(target)
        : expand
        ? selection.expandTo(target, selection.isCollapsed)
        : selection.extendTo(target);
    final crossesBase =
        intent.collapseAtReversal &&
        (selection.baseOffset - selection.extentOffset) *
                (selection.baseOffset - moved.extentOffset) <
            0;
    widget.controller.setSelection(
      crossesBase ? TextSelection.fromPosition(selection.base) : moved,
      requestFocus: false,
    );
    _preferredCursorX = null;
  }

  TextPosition _wordBoundaryTarget(
    TextPosition position, {
    required bool forward,
  }) {
    final document = widget.controller.document;
    final blockIndex = document.blockIndexAt(position.offset);
    final state = _stateForIndex(blockIndex);
    final target = state?.globalWordBoundaryAt(
      forward ? position.offset : position.offset - 1,
      forward: forward,
    );
    if (target != null) {
      return TextPosition(offset: target);
    }
    if (forward) {
      return TextPosition(
        offset: blockIndex + 1 < document.length
            ? document[blockIndex + 1].start
            : document.source.length,
      );
    }
    if (blockIndex <= 0) {
      return const TextPosition(offset: 0);
    }
    final previous = document[blockIndex - 1];
    final previousVisualEnd = previous.separatorEnd > previous.end
        ? previous.separatorEnd - 1
        : previous.separatorEnd;
    return TextPosition(offset: previousVisualEnd);
  }

  TextPosition _lineBoundaryTarget(
    TextPosition position, {
    required bool forward,
  }) {
    final document = widget.controller.document;
    final blockIndex = document.blockIndexAt(position.offset);
    final range = _stateForIndex(blockIndex)?.globalLineBoundary(position);
    if (range != null) {
      return TextPosition(
        offset: forward ? range.end : range.start,
        affinity: forward ? TextAffinity.upstream : TextAffinity.downstream,
      );
    }
    final text = document.source;
    final caretOffset = position.affinity == TextAffinity.upstream
        ? math.max(0, position.offset - 1)
        : position.offset;
    if (forward) {
      final newline = text.indexOf('\n', caretOffset);
      return TextPosition(
        offset: newline < 0 ? text.length : newline,
        affinity: TextAffinity.upstream,
      );
    }
    final newline = caretOffset <= 0
        ? -1
        : text.lastIndexOf('\n', caretOffset - 1);
    return TextPosition(offset: newline + 1);
  }

  TextPosition _paragraphBoundaryTarget(
    TextPosition position, {
    required bool forward,
  }) {
    final boundary = ParagraphBoundary(widget.controller.value.text);
    final offset = forward
        ? boundary.getTrailingTextBoundaryAt(position.offset) ??
              widget.controller.value.text.length
        : boundary.getLeadingTextBoundaryAt(position.offset - 1) ?? 0;
    return TextPosition(offset: offset);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      return _handledKeysDown.remove(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (widget.controller.isComposing) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final hardwareKeyboard = HardwareKeyboard.instance;
    if (hardwareKeyboard.isMetaPressed ||
        hardwareKeyboard.isControlPressed ||
        hardwareKeyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isApplePlatform &&
        hardwareKeyboard.isShiftPressed &&
        key == LogicalKeyboardKey.delete) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.backspace) {
      widget.controller.deleteBackward();
      _preferredCursorX = null;
      return _markKeyHandled(key);
    }
    if (key == LogicalKeyboardKey.delete) {
      widget.controller.deleteForward();
      _preferredCursorX = null;
      return _markKeyHandled(key);
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      widget.controller.replaceSelection('\n');
      _preferredCursorX = null;
      return _markKeyHandled(key);
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      widget.controller.moveHorizontally(
        forward: key == LogicalKeyboardKey.arrowRight,
        extend: _shiftPressed,
      );
      _preferredCursorX = null;
      return _markKeyHandled(key);
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _moveVertically(
        upward: key == LogicalKeyboardKey.arrowUp,
        extend: _shiftPressed,
      );
      return _markKeyHandled(key);
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _markKeyHandled(LogicalKeyboardKey key) {
    _handledKeysDown.add(key);
    return KeyEventResult.handled;
  }

  void _moveVertically({required bool upward, required bool extend}) {
    final selection = widget.controller.selection;
    if (!extend && !selection.isCollapsed) {
      widget.controller.setSelection(
        TextSelection.collapsed(
          offset: upward ? selection.start : selection.end,
        ),
        requestFocus: false,
      );
      return;
    }
    final document = widget.controller.document;
    final currentOffset = selection.extentOffset;
    final currentIndex = document.blockIndexAt(currentOffset);
    final currentState = _stateForIndex(currentIndex);
    final caret = currentState?.localCaretRect(
      currentOffset,
      affinity: selection.affinity,
    );
    final paragraphRect = currentState?.paragraphGlobalRect;
    if (currentState == null || caret == null || paragraphRect == null) {
      unawaited(ensureRangeVisible(TextRange.collapsed(currentOffset)));
      return;
    }

    final preferredX = _preferredCursorX ?? caret.left;
    _preferredCursorX = preferredX;
    final targetY = caret.center.dy + (upward ? -caret.height : caret.height);
    TextPosition? targetPosition;
    if (targetY >= 0 && targetY <= paragraphRect.height) {
      targetPosition = currentState.globalTextPositionForLocalPosition(
        Offset(preferredX, targetY),
      );
    } else {
      final targetIndex = currentIndex + (upward ? -1 : 1);
      final targetState = _stateForIndex(targetIndex);
      final targetRect = targetState?.paragraphGlobalRect;
      if (targetState == null || targetRect == null) {
        if (targetIndex >= 0 && targetIndex < document.length) {
          unawaited(
            ensureRangeVisible(
              TextRange.collapsed(document[targetIndex].start),
            ).then((_) {
              if (mounted) {
                _moveVertically(upward: upward, extend: extend);
              }
            }),
          );
        }
        return;
      }
      targetPosition = targetState.globalTextPositionForLocalPosition(
        Offset(preferredX, upward ? targetRect.height : 0),
      );
    }
    final nextSelection = extend
        ? selection.copyWith(
            extentOffset: targetPosition.offset,
            affinity: targetPosition.affinity,
          )
        : TextSelection.fromPosition(targetPosition);
    widget.controller.setSelection(nextSelection, requestFocus: false);
  }

  void _scheduleCaretVisibility() {
    if (!widget.controller.focusNode.hasFocus) {
      _scheduledSelection = null;
      return;
    }
    final selection = widget.controller.selection;
    if (_scheduledSelection == selection) {
      return;
    }
    _scheduledSelection = selection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keepCaretVisible(selection.extent);
      }
    });
  }

  Future<void> _keepCaretVisible(TextPosition caretPosition) async {
    if (!mounted) {
      return;
    }
    final offset = caretPosition.offset;
    final document = widget.controller.document;
    final blockIndex = document.blockIndexAt(offset);
    var state = _stateForIndex(blockIndex);
    if (state == null) {
      await ensureRangeVisible(TextRange.collapsed(offset));
      if (!mounted) {
        return;
      }
      state = _stateForIndex(blockIndex);
    }
    final caret = state?.globalCaretRect(
      offset,
      affinity: caretPosition.affinity,
    );
    final viewport = _editorGlobalRect;
    final editorBox = _editorRenderBox;
    if (caret == null || viewport == null || editorBox == null) {
      return;
    }
    final localCaret = Rect.fromPoints(
      editorBox.globalToLocal(caret.topLeft),
      editorBox.globalToLocal(caret.bottomRight),
    );
    _inputClient.updateGeometry(caretRect: localCaret);
    if (widget.autoHeight) {
      // 自增高时本体不滚动，交给外层滚动容器按需最小滚动露出光标。
      editorBox.showOnScreen(
        rect: localCaret.inflate(RevericSpacing.sm),
        duration: Duration.zero,
      );
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final topLimit = viewport.top + RevericSpacing.sm;
    final bottomLimit = viewport.bottom - RevericSpacing.sm;
    double delta = 0;
    if (caret.top < topLimit) {
      delta = caret.top - topLimit;
    } else if (caret.bottom > bottomLimit) {
      delta = caret.bottom - bottomLimit;
    }
    if (delta == 0) {
      return;
    }
    final scrollPosition = _scrollController.position;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(
        scrollPosition.minScrollExtent,
        scrollPosition.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleCaretVisibility();
    final document = widget.controller.document;
    final horizontalPadding = RevericSpacing.x3l * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalPadding,
        );
        _metrics.configure(
          availableWidth: widget.style.effectiveTextWidth(availableWidth),
          fontSize: widget.style.textStyle.fontSize ?? 16,
          lineHeight: widget.style.textStyle.height ?? 1,
          letterSpacing: widget.style.textStyle.letterSpacing ?? 0,
        );
        return Shortcuts(
          shortcuts: _additionalTextShortcuts,
          child: Actions(
            actions: _textActions,
            child: Focus(
              focusNode: widget.controller.focusNode,
              canRequestFocus: widget.enabled,
              onKeyEvent: _handleKeyEvent,
              child: MouseRegion(
                cursor: widget.enabled
                    ? SystemMouseCursors.text
                    : MouseCursor.defer,
                child: Stack(
                  key: _editorKey,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      supportedDevices: _touchSelectionDevices,
                      onTapUp: _handleTouchTap,
                      child: RawGestureDetector(
                        behavior: HitTestBehavior.translucent,
                        gestures: <Type, GestureRecognizerFactory>{
                          TapAndPanGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                TapAndPanGestureRecognizer
                              >(
                                () => TapAndPanGestureRecognizer(
                                  debugOwner: this,
                                  supportedDevices: _desktopSelectionDevices,
                                ),
                                (recognizer) {
                                  recognizer
                                    ..dragStartBehavior = DragStartBehavior.down
                                    ..onTapDown = _handleDesktopTapDown
                                    ..onTapUp = _handleDesktopTapUp
                                    ..onDragStart = _handleSelectionDragStart
                                    ..onDragUpdate = _handleSelectionDragUpdate
                                    ..onDragEnd = _handleSelectionDragEnd
                                    ..onCancel = _finishSelectionDrag;
                                },
                              ),
                          // 右键单独走 TapGestureRecognizer：
                          // TapAndPanGestureRecognizer 只接受主键，不会重复响应。
                          TapGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                TapGestureRecognizer
                              >(
                                () => TapGestureRecognizer(
                                  debugOwner: this,
                                  supportedDevices: _desktopSelectionDevices,
                                ),
                                (recognizer) {
                                  recognizer.onSecondaryTapDown =
                                      _handleSecondaryTapDown;
                                },
                              ),
                          // 触屏长按选词并拖动扩选；与滚动手势正常竞争，
                          // 超时前移动超过 touch slop 时让位给滚动。
                          LongPressGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                LongPressGestureRecognizer
                              >(
                                () => LongPressGestureRecognizer(
                                  debugOwner: this,
                                  supportedDevices: _touchSelectionDevices,
                                ),
                                (recognizer) {
                                  recognizer
                                    ..onLongPressStart =
                                        _handleTouchLongPressStart
                                    ..onLongPressMoveUpdate =
                                        _handleTouchLongPressMoveUpdate
                                    ..onLongPressEnd = _handleTouchLongPressEnd
                                    ..onLongPressCancel =
                                        _handleTouchLongPressCancel;
                                },
                              ),
                        },
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.minHeight,
                          ),
                          child: CustomScrollView(
                            controller: _scrollController,
                            shrinkWrap: widget.autoHeight,
                            physics: widget.autoHeight
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              300,
                            ),
                            slivers: <Widget>[
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  RevericSpacing.x3l,
                                  RevericSpacing.x3l,
                                  RevericSpacing.x3l,
                                  RevericSpacing.x3l +
                                      (widget.autoHeight
                                          ? _touchMenuReserveBottom()
                                          : 0),
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final block = document[index];
                                      return MarkdownReadonlyBlock(
                                        key: _keyFor(block.id),
                                        controller: widget.controller,
                                        block: block,
                                        style: widget.style,
                                        enabled: widget.enabled,
                                        hintText: index == 0
                                            ? widget.hintText
                                            : '',
                                      );
                                    },
                                    childCount: document.length,
                                    findChildIndexCallback: (key) {
                                      if (key is! GlobalKey) {
                                        return null;
                                      }
                                      for (
                                        var index = 0;
                                        index < document.length;
                                        index++
                                      ) {
                                        if (_blockKeys[document[index].id] ==
                                            key) {
                                          return index;
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 手柄与菜单位于手势层之上，避免命中落入单击收起的检测器。
                    // 贴底选区会通过 [_touchMenuReserveBottom] 加高编辑器，避免菜单被圆角裁掉。
                    ..._buildTouchSelectionOverlays(context, constraints),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 触屏选区的手柄与浮动菜单。几何取自当前挂载块的 caret 矩形，
  /// 块被虚拟化卸载时对应控件自动隐藏。
  List<Widget> _buildTouchSelectionOverlays(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (!_touchSelectionActive) {
      return const <Widget>[];
    }
    final selection = widget.controller.selection;
    final editorBox = _editorRenderBox;
    if (editorBox == null || !editorBox.attached) {
      return const <Widget>[];
    }
    final colors = RevericTheme.colorsOf(context);
    var startCaret = _localCaretRect(editorBox, selection.start);
    var endCaret = _localCaretRect(editorBox, selection.end);
    if (selection.isCollapsed && startCaret == null && endCaret == null) {
      startCaret = endCaret = _fallbackCollapsedCaretLocal();
    }
    final overlays = <Widget>[];
    if (!selection.isCollapsed) {
      if (startCaret != null) {
        overlays.add(_buildHandle(colors, startCaret, isStart: true));
      }
      if (endCaret != null) {
        overlays.add(_buildHandle(colors, endCaret, isStart: false));
      }
    }
    final menu = _buildTouchMenu(
      context,
      startCaret,
      endCaret,
      constraints.maxWidth,
    );
    if (menu != null) {
      overlays.add(menu);
    }
    return overlays;
  }

  Rect? _localCaretRect(RenderBox editorBox, int offset) {
    final globalRect = _globalCaretRectForOffset(offset);
    if (globalRect == null) {
      return null;
    }
    return Rect.fromPoints(
      editorBox.globalToLocal(globalRect.topLeft),
      editorBox.globalToLocal(globalRect.bottomRight),
    );
  }

  Rect _fallbackCollapsedCaretLocal() {
    return Rect.fromLTWH(
      RevericSpacing.x3l,
      RevericSpacing.x3l,
      MarkdownBlockStyle.cursorWidth,
      20,
    );
  }

  Widget _buildHandle(
    RevericColors colors,
    Rect caretLocal, {
    required bool isStart,
  }) {
    return Positioned(
      left: caretLocal.center.dx - _touchHandleHitSize / 2,
      top: caretLocal.top,
      width: _touchHandleHitSize,
      height:
          caretLocal.height +
          _touchHandleGap +
          _touchHandleCircleRadius * 2 +
          RevericSpacing.xxs,
      child: _SelectionHandle(
        key: ValueKey<String>(
          isStart ? 'markdownTouchHandleStart' : 'markdownTouchHandleEnd',
        ),
        color: colors.accent,
        lineHeight: caretLocal.height,
        onDragStart: (details) =>
            _handleSelectionHandleDragStart(isStart, details),
        onDragUpdate: _handleSelectionHandleDragUpdate,
        onDragEnd: _handleSelectionHandleDragEnd,
      ),
    );
  }

  /// 菜单优先放在选区起点上方；贴近顶部时翻转到终点下方。
  /// 贴底时由 [_touchMenuReserveBottom] 加高编辑器，避免被 ClipRRect 裁掉。
  Widget? _buildTouchMenu(
    BuildContext context,
    Rect? startCaret,
    Rect? endCaret,
    double editorWidth,
  ) {
    if (_handleDragInProgress || _longPressWordRange != null) {
      return null;
    }
    if (_menuHiddenFor == widget.controller.selection) {
      return null;
    }
    final anchor = startCaret ?? endCaret;
    if (anchor == null) {
      return null;
    }
    final menuTop = _touchMenuTop(startCaret, endCaret);
    if (menuTop == null) {
      return null;
    }
    final collapsedCaret = widget.controller.selection.isCollapsed;
    final halfWidth = collapsedCaret
        ? _touchCaretMenuHalfWidth
        : _touchMenuHalfWidth;
    final centerX = anchor.center.dx
        .clamp(halfWidth, math.max(halfWidth, editorWidth - halfWidth))
        .toDouble();
    return Positioned(
      left: centerX,
      top: menuTop,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: _TouchSelectionMenu(
          collapsedCaret: collapsedCaret,
          onCut: _handleMenuCut,
          onCopy: _handleMenuCopy,
          onPaste: _handleMenuPaste,
          onSelectAll: _handleMenuSelectAll,
          onNewline: _handleMenuNewline,
        ),
      ),
    );
  }

  /// 菜单相对未加高前的内容底部超出多少；加到 sliver 底 padding，让短字段也能放下菜单。
  double _touchMenuReserveBottom() {
    if (!_touchSelectionActive ||
        _handleDragInProgress ||
        _longPressWordRange != null ||
        _menuHiddenFor == widget.controller.selection) {
      return 0;
    }
    final editorBox = _editorRenderBox;
    if (editorBox == null || !editorBox.attached) {
      return 0;
    }
    final selection = widget.controller.selection;
    final startCaret = _localCaretRect(editorBox, selection.start);
    final endCaret = _localCaretRect(editorBox, selection.end);
    final anchor = startCaret ?? endCaret;
    if (anchor == null) {
      return 0;
    }
    final menuTop = _touchMenuTop(startCaret, endCaret);
    if (menuTop == null) {
      return 0;
    }
    final naturalBottom = (endCaret ?? anchor).bottom + RevericSpacing.x3l;
    return math.max(0.0, menuTop + _touchMenuHeight - naturalBottom);
  }

  double? _touchMenuTop(Rect? startCaret, Rect? endCaret) {
    final anchor = startCaret ?? endCaret;
    if (anchor == null) {
      return null;
    }
    var top = anchor.top - _touchMenuHeight - RevericSpacing.sm;
    if (top < 0) {
      final below = endCaret ?? anchor;
      top = below.bottom + RevericSpacing.sm;
    }
    return top;
  }
}

class _ComposingAwareCallbackAction<T extends Intent>
    extends CallbackAction<T> {
  _ComposingAwareCallbackAction({
    required this._isEnabled,
    required super.onInvoke,
  });

  final bool Function() _isEnabled;

  @override
  bool isEnabled(T intent) => _isEnabled();
}

/// 触屏选区端点的拖动手柄：竖线对齐 caret，圆点垂在行下方。
/// 命中区 44px 由外层 Positioned 给定，绘制居中于命中区。
class _SelectionHandle extends StatelessWidget {
  const _SelectionHandle({
    super.key,
    required this.color,
    required this.lineHeight,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Color color;
  final double lineHeight;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onDragStart,
      onPanUpdate: onDragUpdate,
      onPanEnd: onDragEnd,
      onPanCancel: () => onDragEnd(DragEndDetails()),
      child: CustomPaint(
        painter: _SelectionHandlePainter(color: color, lineHeight: lineHeight),
      ),
    );
  }
}

class _SelectionHandlePainter extends CustomPainter {
  const _SelectionHandlePainter({
    required this.color,
    required this.lineHeight,
  });

  final Color color;
  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final centerX = size.width / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        centerX - MarkdownBlockStyle.cursorWidth / 2,
        0,
        MarkdownBlockStyle.cursorWidth,
        lineHeight,
      ),
      paint,
    );
    canvas.drawCircle(
      Offset(centerX, lineHeight + _touchHandleGap + _touchHandleCircleRadius),
      _touchHandleCircleRadius,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionHandlePainter oldDelegate) {
    return color != oldDelegate.color || lineHeight != oldDelegate.lineHeight;
  }
}

/// 触屏选区的浮动操作菜单：选区为剪切 / 复制 / 粘贴 / 全选，空白光标为粘贴 / 换行。
class _TouchSelectionMenu extends StatelessWidget {
  const _TouchSelectionMenu({
    required this.collapsedCaret,
    required this.onCut,
    required this.onCopy,
    required this.onPaste,
    required this.onSelectAll,
    required this.onNewline,
  });

  final bool collapsedCaret;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onSelectAll;
  final VoidCallback onNewline;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      key: const ValueKey<String>('markdownTouchSelectionMenu'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: collapsedCaret
            ? <Widget>[
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuPaste'),
                  label: LocaleKeys.commonPaste,
                  onPressed: onPaste,
                ),
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuNewline'),
                  label: LocaleKeys.commonNewline,
                  onPressed: onNewline,
                ),
              ]
            : <Widget>[
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuCut'),
                  label: LocaleKeys.commonCut,
                  onPressed: onCut,
                ),
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuCopy'),
                  label: LocaleKeys.commonCopy,
                  onPressed: onCopy,
                ),
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuPaste'),
                  label: LocaleKeys.commonPaste,
                  onPressed: onPaste,
                ),
                _menuButton(
                  context,
                  key: const ValueKey<String>('markdownTouchMenuSelectAll'),
                  label: LocaleKeys.commonSelectAll,
                  onPressed: onSelectAll,
                ),
              ],
      ),
    );
  }

  Widget _menuButton(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.textSecondary,
        minimumSize: const Size(0, _touchMenuHeight),
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(context.t(label), style: typo.ui),
    );
  }
}
