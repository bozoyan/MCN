// 职责: 文本编辑器搜索替换层 — 为 TextEditingController 驱动的编辑器提供查找、替换与桌面快捷键。
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

typedef EnsureTextRangeVisible =
    void Function(TextRange range, {required bool focusEditor});

class TextFindReplaceScope extends StatefulWidget {
  const TextFindReplaceScope({
    super.key,
    required this.controller,
    required this.editorFocusNode,
    required this.child,
    this.enabled = true,
    this.metaShortcutsEnabled = true,
    this.controlShortcutsEnabled = true,
    this.ensureRangeVisible,
    this.overlayInViewport = false,
    this.replaceRanges,
  });

  final TextEditingController controller;
  final void Function(List<TextRange> ranges, String replacement)?
  replaceRanges;
  final FocusNode editorFocusNode;
  final Widget child;
  final bool enabled;
  final bool metaShortcutsEnabled;
  final bool controlShortcutsEnabled;
  final EnsureTextRangeVisible? ensureRangeVisible;

  /// 正文由外层滚动时，把查找栏放在视口浮层，避免随正文滚出屏幕。
  final bool overlayInViewport;

  /// 返回当前搜索匹配，供自定义文本绘制在编辑器失焦时继续显示高亮。
  static TextRange? activeMatchOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TextFindActiveMatchScope>()
        ?.activeMatch;
  }

  @override
  State<TextFindReplaceScope> createState() => _TextFindReplaceScopeState();
}

class _TextFindReplaceScopeState extends State<TextFindReplaceScope> {
  late final TextEditingController _queryController;
  late final TextEditingController _replaceController;
  late final FocusNode _queryFocusNode;
  late final FocusNode _replaceFocusNode;
  final _overlay = OverlayPortalController();
  bool _visible = false;
  bool _replaceVisible = false;
  bool _matchCase = false;
  String _debouncedQuery = '';
  int _activeMatchIndex = -1;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _replaceController = TextEditingController();
    _queryFocusNode = FocusNode();
    _replaceFocusNode = FocusNode();
    widget.controller.addListener(_handleEditorChanged);
  }

  @override
  void didUpdateWidget(covariant TextFindReplaceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleEditorChanged);
      widget.controller.addListener(_handleEditorChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleEditorChanged);
    _queryController.dispose();
    _replaceController.dispose();
    _queryFocusNode.dispose();
    _replaceFocusNode.dispose();
    super.dispose();
  }

  void _setEffectiveQuery(
    String query, {
    required bool selectMatch,
    bool advanceIfUnchanged = false,
  }) {
    final queryChanged = _debouncedQuery != query;
    if (queryChanged) {
      setState(() {
        _debouncedQuery = query;
        _activeMatchIndex = -1;
      });
    }
    if (!_visible || query.isEmpty || !selectMatch) {
      return;
    }

    if (queryChanged || _currentMatchIndex(_matches()) < 0) {
      _selectMatch(
        forward: true,
        wrap: true,
        fromSelection: false,
        focusEditor: false,
        resetToFirst: true,
      );
      return;
    }

    if (advanceIfUnchanged) {
      _selectMatch(
        forward: true,
        wrap: true,
        fromSelection: false,
        focusEditor: false,
      );
    }
  }

  void _handleDebouncedQueryChanged(String query) {
    _setEffectiveQuery(query, selectMatch: true);
  }

  void _handleEditorChanged() {
    if (_visible) {
      final matches = _matches();
      final selectedIndex = _selectionMatchIndex(matches);
      setState(() {
        if (selectedIndex >= 0) {
          _activeMatchIndex = selectedIndex;
        } else if (_activeMatchIndex >= matches.length) {
          _activeMatchIndex = matches.isEmpty ? -1 : matches.length - 1;
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final metaPressed = HardwareKeyboard.instance.isMetaPressed;
    final controlPressed = HardwareKeyboard.instance.isControlPressed;
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final isModifierPressed =
        (isMacOS && widget.metaShortcutsEnabled && metaPressed) ||
        (widget.controlShortcutsEnabled && controlPressed);
    if (!isModifierPressed) {
      if (event.logicalKey == LogicalKeyboardKey.escape && _visible) {
        _hide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (HardwareKeyboard.instance.isAltPressed) {
        _show(replace: true);
        return KeyEventResult.handled;
      }
      _show(replace: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      _show(replace: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyG && _visible) {
      _selectMatch(
        forward: !HardwareKeyboard.instance.isShiftPressed,
        wrap: true,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _show({required bool replace}) {
    final selected = widget.controller.selection.isValid
        ? widget.controller.selection.textInside(widget.controller.text)
        : '';
    setState(() {
      _visible = true;
      _replaceVisible = replace || _replaceVisible;
      if (selected.isNotEmpty &&
          !selected.contains('\n') &&
          !selected.contains('\u2029') &&
          !selected.contains('\uFFFC')) {
        _queryController.text = selected;
        _queryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: selected.length,
        );
      }
    });
    if (widget.overlayInViewport) {
      _overlay.show();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _queryFocusNode.requestFocus();
      if (_queryController.text.isNotEmpty) {
        _queryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _queryController.text.length,
        );
      }
    });
  }

  void _hide() {
    if (widget.overlayInViewport) {
      _overlay.hide();
    }
    setState(() {
      _visible = false;
      _activeMatchIndex = -1;
    });
    widget.editorFocusNode.requestFocus();
  }

  /// 匹配结果缓存：查找栏可见时正文每次输入都会重建，重复扫描（含忽略大小写的
  /// 全文 `toLowerCase`）代价随正文线性增长，这里按正文 + 查询词 + 大小写缓存。
  List<TextRange>? _cachedMatches;
  String? _cachedMatchesText;
  String? _cachedMatchesQuery;
  bool? _cachedMatchesCaseSensitive;

  List<TextRange> _matches() {
    final query = _debouncedQuery;
    if (query.isEmpty) {
      return const [];
    }

    final source = widget.controller.text;
    final cached = _cachedMatches;
    if (cached != null &&
        _cachedMatchesText == source &&
        _cachedMatchesQuery == query &&
        _cachedMatchesCaseSensitive == _matchCase) {
      return cached;
    }

    final haystack = _matchCase ? source : source.toLowerCase();
    final needle = _matchCase ? query : query.toLowerCase();
    final result = <TextRange>[];
    var index = 0;
    while (index <= haystack.length - needle.length) {
      final found = haystack.indexOf(needle, index);
      if (found < 0) {
        break;
      }
      result.add(TextRange(start: found, end: found + needle.length));
      index = found + needle.length;
    }

    _cachedMatches = result;
    _cachedMatchesText = source;
    _cachedMatchesQuery = query;
    _cachedMatchesCaseSensitive = _matchCase;
    return result;
  }

  int _selectionMatchIndex(List<TextRange> matches) {
    final selection = widget.controller.selection;
    if (!selection.isValid) {
      return -1;
    }
    return matches.indexWhere(
      (range) => range.start == selection.start && range.end == selection.end,
    );
  }

  int _currentMatchIndex(List<TextRange> matches) {
    if (_activeMatchIndex >= 0 && _activeMatchIndex < matches.length) {
      return _activeMatchIndex;
    }
    return _selectionMatchIndex(matches);
  }

  void _setActiveMatchIndex(int index) {
    if (_activeMatchIndex == index) {
      return;
    }
    setState(() {
      _activeMatchIndex = index;
    });
  }

  void _selectMatch({
    required bool forward,
    bool wrap = true,
    bool fromSelection = true,
    bool focusEditor = true,
    bool resetToFirst = false,
  }) {
    final matches = _matches();
    if (matches.isEmpty) {
      _setActiveMatchIndex(-1);
      return;
    }

    final selection = widget.controller.selection;
    final currentIndex = resetToFirst ? -1 : _currentMatchIndex(matches);
    var nextIndex = 0;
    if (!resetToFirst && currentIndex >= 0) {
      nextIndex = forward ? currentIndex + 1 : currentIndex - 1;
    } else if (fromSelection && selection.isValid) {
      if (forward) {
        nextIndex = matches.indexWhere((range) => range.start >= selection.end);
        if (nextIndex < 0) {
          nextIndex = wrap ? 0 : matches.length - 1;
        }
      } else {
        nextIndex = matches.lastIndexWhere(
          (range) => range.end <= selection.start,
        );
        if (nextIndex < 0) {
          nextIndex = wrap ? matches.length - 1 : 0;
        }
      }
    }

    if (wrap) {
      if (nextIndex >= matches.length) {
        nextIndex = 0;
      } else if (nextIndex < 0) {
        nextIndex = matches.length - 1;
      }
    } else {
      nextIndex = nextIndex.clamp(0, matches.length - 1);
    }

    final target = matches[nextIndex];
    _setActiveMatchIndex(nextIndex);
    _selectRange(target, focusEditor: focusEditor);
  }

  void _selectRange(TextRange range, {bool focusEditor = true}) {
    widget.controller.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    if (focusEditor) {
      widget.editorFocusNode.requestFocus();
    }
    // 程序化改 selection 不会走 EditableText 的键盘/拖拽 bringIntoView 路径，
    // 需要主动把匹配滚进视口（章节编辑器外层有 SingleChildScrollView）。
    _ensureSelectionVisible(range, focusEditor: focusEditor);
  }

  void _ensureSelectionVisible(TextRange range, {required bool focusEditor}) {
    final injected = widget.ensureRangeVisible;
    if (injected != null) {
      injected(range, focusEditor: focusEditor);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final editableContext = widget.editorFocusNode.context;
      if (editableContext == null) {
        return;
      }
      final renderEditable = _findRenderEditable(editableContext);
      if (renderEditable == null) {
        return;
      }
      final boxes = renderEditable.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      final Rect localRect;
      if (boxes.isEmpty) {
        localRect = renderEditable.getLocalRectForCaret(
          TextPosition(offset: range.start),
        );
      } else {
        localRect = boxes
            .map((box) => box.toRect())
            .reduce((a, b) => a.expandToInclude(b));
      }
      renderEditable.showOnScreen(rect: localRect);
    });
  }

  RenderEditable? _findRenderEditable(BuildContext context) {
    final self = context.findRenderObject();
    if (self is RenderEditable) {
      return self;
    }
    RenderEditable? found;
    void visit(Element element) {
      if (found != null) {
        return;
      }
      final renderObject = element.renderObject;
      if (renderObject is RenderEditable) {
        found = renderObject;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  void _replaceCurrent() {
    var matches = _matches();
    if (matches.isEmpty) {
      return;
    }
    var index = _currentMatchIndex(matches);
    if (index < 0) {
      _selectMatch(forward: true);
      matches = _matches();
      index = _currentMatchIndex(matches);
      if (index < 0) {
        return;
      }
    }

    final range = matches[index];
    final replacement = _replaceController.text;
    if (widget.replaceRanges case final replace?) {
      replace([range], replacement);
      _setActiveMatchIndex(-1);
      return;
    }
    final text = widget.controller.text;
    _setActiveMatchIndex(-1);
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(range.start, range.end, replacement),
      selection: TextSelection.collapsed(
        offset: range.start + replacement.length,
      ),
    );
    _selectMatch(forward: true);
  }

  void _replaceAll() {
    final query = _debouncedQuery;
    if (query.isEmpty) {
      return;
    }
    final matches = _matches();
    if (matches.isEmpty) {
      return;
    }
    final replacement = _replaceController.text;
    if (widget.replaceRanges case final replace?) {
      replace(matches, replacement);
      _setActiveMatchIndex(-1);
      return;
    }
    final buffer = StringBuffer();
    var cursor = 0;
    final text = widget.controller.text;
    for (final match in matches) {
      buffer
        ..write(text.substring(cursor, match.start))
        ..write(replacement);
      cursor = match.end;
    }
    buffer.write(text.substring(cursor));
    _setActiveMatchIndex(-1);
    widget.controller.value = TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
    widget.editorFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // 查找栏隐藏时不存在高亮，直接跳过全文扫描。
    final matches = _visible ? _matches() : const <TextRange>[];
    final currentMatchIndex = _currentMatchIndex(matches);
    final activeMatch = _visible && currentMatchIndex >= 0
        ? matches[currentMatchIndex]
        : null;
    final bar = _FindReplaceBar(
      queryController: _queryController,
      replaceController: _replaceController,
      queryFocusNode: _queryFocusNode,
      replaceFocusNode: _replaceFocusNode,
      replaceVisible: _replaceVisible,
      matchCase: _matchCase,
      debouncedQuery: _debouncedQuery,
      matchCount: matches.length,
      currentMatchIndex: currentMatchIndex,
      onQueryDebounced: _handleDebouncedQueryChanged,
      onQuerySubmitted: (query) {
        _setEffectiveQuery(query, selectMatch: true, advanceIfUnchanged: true);
      },
      onPrevious: () => _selectMatch(forward: false),
      onNext: () => _selectMatch(forward: true),
      onReplace: _replaceCurrent,
      onReplaceAll: _replaceAll,
      onToggleReplace: () {
        setState(() {
          _replaceVisible = !_replaceVisible;
        });
      },
      onToggleMatchCase: () {
        setState(() {
          _matchCase = !_matchCase;
          _activeMatchIndex = -1;
        });
        _selectMatch(
          forward: true,
          wrap: true,
          fromSelection: false,
          focusEditor: false,
          resetToFirst: true,
        );
      },
      onClose: _hide,
    );
    final content = _TextFindActiveMatchScope(
      activeMatch: activeMatch,
      child: widget.child,
    );
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: widget.overlayInViewport
          ? OverlayPortal(
              controller: _overlay,
              overlayChildBuilder: (_) => _floatingBar(bar),
              child: content,
            )
          : Stack(
              children: [
                content,
                if (_visible)
                  Positioned(
                    top: RevericSpacing.md,
                    right: RevericSpacing.md,
                    child: bar,
                  ),
              ],
            ),
    );
  }

  Widget _floatingBar(Widget bar) {
    final screen = MediaQuery.sizeOf(context);
    final root = context.findRenderObject()!;
    final viewport = RenderAbstractViewport.maybeOf(root);
    final box = (viewport is RenderBox ? viewport : root) as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(overlayBox),
      Offset.zero & box.size,
    ).intersect(Offset.zero & screen);
    final width = math.min(
      420.0,
      math.max(0.0, bounds.width - RevericSpacing.md * 2),
    );
    return Positioned(
      top: bounds.top + RevericSpacing.md,
      left: bounds.right - RevericSpacing.md - width,
      width: width,
      child: bar,
    );
  }
}

class _TextFindActiveMatchScope extends InheritedWidget {
  const _TextFindActiveMatchScope({
    required this.activeMatch,
    required super.child,
  });

  final TextRange? activeMatch;

  @override
  bool updateShouldNotify(_TextFindActiveMatchScope oldWidget) {
    return oldWidget.activeMatch != activeMatch;
  }
}

class _FindReplaceBar extends StatelessWidget {
  const _FindReplaceBar({
    required this.queryController,
    required this.replaceController,
    required this.queryFocusNode,
    required this.replaceFocusNode,
    required this.replaceVisible,
    required this.matchCase,
    required this.debouncedQuery,
    required this.matchCount,
    required this.currentMatchIndex,
    required this.onQueryDebounced,
    required this.onQuerySubmitted,
    required this.onPrevious,
    required this.onNext,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onToggleReplace,
    required this.onToggleMatchCase,
    required this.onClose,
  });

  final TextEditingController queryController;
  final TextEditingController replaceController;
  final FocusNode queryFocusNode;
  final FocusNode replaceFocusNode;
  final bool replaceVisible;
  final bool matchCase;
  final String debouncedQuery;
  final int matchCount;
  final int currentMatchIndex;
  final ValueChanged<String> onQueryDebounced;
  final ValueChanged<String> onQuerySubmitted;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleReplace;
  final VoidCallback onToggleMatchCase;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final rawQuery = queryController.text;
    final querySettled = rawQuery == debouncedQuery;
    final canAct = querySettled && debouncedQuery.isNotEmpty && matchCount > 0;
    final countText = rawQuery.isEmpty || !querySettled
        ? ''
        : matchCount == 0
        ? context.t(LocaleKeys.commonNoResults)
        : '${currentMatchIndex + 1}/$matchCount';

    return Material(
      elevation: 10,
      shadowColor: colors.textPrimary.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(RevericRadius.large),
      color: colors.surfaceContainer,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(RevericSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _FindIconButton(
                  tooltip: context.t(LocaleKeys.editorFindReplace),
                  icon: replaceVisible
                      ? RevericIcons.expand_more_rounded
                      : RevericIcons.keyboard_arrow_right,
                  onPressed: onToggleReplace,
                ),
                Expanded(
                  child: _FindTextField(
                    controller: queryController,
                    focusNode: queryFocusNode,
                    hintText: context.t(LocaleKeys.editorFind),
                    onDebouncedChanged: onQueryDebounced,
                    onSubmitted: onQuerySubmitted,
                  ),
                ),
                const SizedBox(width: RevericSpacing.xs),
                SizedBox(
                  width: 64,
                  child: Text(
                    countText,
                    textAlign: TextAlign.center,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _FindIconButton(
                  tooltip: context.t(LocaleKeys.editorFindPrevious),
                  icon: RevericIcons.keyboard_arrow_up,
                  onPressed: canAct ? onPrevious : null,
                ),
                _FindIconButton(
                  tooltip: context.t(LocaleKeys.editorFindNext),
                  icon: RevericIcons.keyboard_arrow_down,
                  onPressed: canAct ? onNext : null,
                ),
                _FindIconButton(
                  tooltip: context.t(LocaleKeys.editorMatchCase),
                  label: 'Aa',
                  selected: matchCase,
                  onPressed: onToggleMatchCase,
                ),
                _FindIconButton(
                  tooltip: context.t(LocaleKeys.commonClose),
                  icon: RevericIcons.close,
                  onPressed: onClose,
                ),
              ],
            ),
            if (replaceVisible) ...[
              const SizedBox(height: RevericSpacing.xs),
              Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: _FindTextField(
                      controller: replaceController,
                      focusNode: replaceFocusNode,
                      hintText: context.t(LocaleKeys.editorReplaceWith),
                      onSubmitted: (_) => onReplace(),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  TextButton(
                    onPressed: canAct ? onReplace : null,
                    child: Text(context.t(LocaleKeys.editorReplaceOne)),
                  ),
                  TextButton(
                    onPressed: canAct ? onReplaceAll : null,
                    child: Text(context.t(LocaleKeys.editorReplaceAll)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FindTextField extends StatelessWidget {
  const _FindTextField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
    this.onDebouncedChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onDebouncedChanged;

  @override
  Widget build(BuildContext context) {
    if (onDebouncedChanged != null) {
      return _DebouncedFindTextField(
        controller: controller,
        focusNode: focusNode,
        hintText: hintText,
        onSubmitted: onSubmitted,
        onDebouncedChanged: onDebouncedChanged!,
      );
    }
    return _FindTextFieldContent(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      onSubmitted: onSubmitted,
    );
  }
}

class _DebouncedFindTextField extends HookWidget {
  const _DebouncedFindTextField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
    required this.onDebouncedChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onDebouncedChanged;

  @override
  Widget build(BuildContext context) {
    final textValue = useValueListenable(controller);
    final rawQuery = textValue.text;
    final debouncedQuery = useDebounced(
      rawQuery,
      const Duration(milliseconds: 250),
    );

    useEffect(() {
      final nextQuery = rawQuery.isEmpty ? '' : debouncedQuery;
      if (nextQuery == null) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          onDebouncedChanged(nextQuery);
        }
      });
      return null;
    }, [rawQuery, debouncedQuery, onDebouncedChanged]);

    return _FindTextFieldContent(
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      onSubmitted: onSubmitted,
    );
  }
}

class _FindTextFieldContent extends StatelessWidget {
  const _FindTextFieldContent({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted,
        style: typo.uiSmall.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          hintText: hintText,
          hintStyle: typo.uiSmall.copyWith(color: colors.textSubtle),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.sm,
            vertical: RevericSpacing.xs,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RevericRadius.small),
            borderSide: BorderSide(color: colors.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RevericRadius.small),
            borderSide: BorderSide(color: colors.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(RevericRadius.small),
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
      ),
    );
  }
}

class _FindIconButton extends StatelessWidget {
  const _FindIconButton({
    required this.tooltip,
    this.icon,
    this.label,
    this.selected = false,
    this.onPressed,
  }) : assert(icon != null || label != null);

  final String tooltip;
  final String? icon;
  final String? label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final enabled = onPressed != null;
    final foreground = !enabled
        ? colors.textSubtle
        : selected
        ? colors.accent
        : colors.textMuted;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            backgroundColor: selected
                ? colors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RevericRadius.small),
            ),
          ),
          child: label == null
              ? RevericIcon(icon!, size: 16, color: foreground)
              : Text(
                  label!,
                  style: typo.uiTiny.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
