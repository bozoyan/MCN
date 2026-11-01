// 职责: 章节大纲独立窗口 — 在共享子窗口外壳中承载大纲编辑，并与主窗口双向同步文本。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/desktop/widgets/detached_window.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import '../desktop_window_frame.dart';
import '../detached_window.dart';

class ChapterOutlineWindowAppearance {
  const ChapterOutlineWindowAppearance({
    required this.theme,
    this.customBaseTheme,
    this.lightOverrides = const {},
    this.darkOverrides = const {},
    required this.themeMode,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
  });

  static const defaults = ChapterOutlineWindowAppearance(
    theme: AppTheme.classic,
    themeMode: AppThemeMode.light,
    fontFamily: 'Georgia',
    fontSize: 16,
    letterSpacing: 0,
    lineHeight: 1.8,
  );

  final AppTheme theme;
  final String? customBaseTheme;
  final Map<String, String> lightOverrides;
  final Map<String, String> darkOverrides;
  final AppThemeMode themeMode;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;

  DetachedWindowTheme get windowTheme => DetachedWindowTheme(
    theme: theme,
    customBaseTheme: customBaseTheme,
    lightOverrides: lightOverrides,
    darkOverrides: darkOverrides,
    themeMode: themeMode,
  );

  RevericThemeData themeDataForBrightness(Brightness brightness) {
    return windowTheme.themeDataForBrightness(brightness);
  }
}

class ChapterOutlineWindowSession {
  ChapterOutlineWindowSession({
    required this.titleController,
    required this.outlineController,
  }) : _detachedOutlineController = TextEditingController(
         text: outlineController.text,
       ) {
    titleController.addListener(_handleTitleChanged);
    outlineController.addListener(_syncMainOutlineToDetached);
    _detachedOutlineController.addListener(_scheduleDetachedOutlineSync);
  }

  final TextEditingController titleController;
  final TextEditingController outlineController;
  final TextEditingController _detachedOutlineController;
  final DetachedWindowSession _window = DetachedWindowSession(
    // 沿用改造前的 key，保留用户已调整好的窗口尺寸与位置。
    placementKey: 'chapter_outline_window_size',
    defaultSize: const Size(640, 640),
    constraints: const BoxConstraints(minWidth: 440, minHeight: 360),
    logModule: 'OutlineWindow',
  );

  bool _disposed = false;
  bool _applyingMainOutline = false;
  bool _applyingDetachedOutline = false;
  String _fallbackTitle = '';
  ChapterOutlineWindowAppearance _appearance =
      ChapterOutlineWindowAppearance.defaults;
  Timer? _outlineSyncTimer;

  @visibleForTesting
  TextEditingController get detachedOutlineController =>
      _detachedOutlineController;

  bool get isWindowOpen => _window.isWindowOpen;

  /// 立即把独立窗口里未 debounce 完的大纲写回主 controller。
  void flushDetachedOutlineSync() {
    if (_disposed) {
      return;
    }
    _outlineSyncTimer?.cancel();
    _outlineSyncTimer = null;
    _syncDetachedOutlineToMain();
  }

  /// 关闭独立窗口。先 flush 文本，再走与系统关窗相同的 destroy 路径。
  Future<void> closeWindow() async {
    if (_disposed) {
      return;
    }
    flushDetachedOutlineSync();
    await _window.close();
  }

  Future<void> open(
    ChapterOutlineWindowAppearance appearance, {
    required String fallbackTitle,
  }) {
    if (_disposed) {
      return Future<void>.value();
    }
    _fallbackTitle = fallbackTitle;
    _appearance = appearance;
    return _window.open(title: _effectiveTitle, theme: appearance.windowTheme);
  }

  String get _effectiveTitle {
    final title = titleController.text.trim();
    return title.isEmpty ? _fallbackTitle : title;
  }

  void _handleTitleChanged() {
    if (_disposed) {
      return;
    }
    _window.setTitle(_effectiveTitle);
  }

  void _syncMainOutlineToDetached() {
    if (_disposed || _applyingDetachedOutline) {
      return;
    }
    final outline = outlineController.text;
    if (_detachedOutlineController.text == outline) {
      return;
    }
    final currentOffset = _detachedOutlineController.selection.baseOffset;
    final nextOffset = currentOffset < 0
        ? outline.length
        : currentOffset.clamp(0, outline.length).toInt();
    _applyingMainOutline = true;
    _detachedOutlineController.value = TextEditingValue(
      text: outline,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _applyingMainOutline = false;
  }

  void _scheduleDetachedOutlineSync() {
    if (_disposed || _applyingMainOutline) {
      return;
    }
    _outlineSyncTimer?.cancel();
    if (_detachedOutlineController.value.composing.isValid) {
      return;
    }
    _outlineSyncTimer = Timer(
      const Duration(milliseconds: 300),
      _syncDetachedOutlineToMain,
    );
  }

  void _syncDetachedOutlineToMain() {
    if (_disposed) {
      return;
    }
    final outline = _detachedOutlineController.text;
    if (outlineController.text == outline) {
      return;
    }
    _applyingDetachedOutline = true;
    outlineController.value = TextEditingValue(
      text: outline,
      selection: TextSelection.collapsed(offset: outline.length),
    );
    _applyingDetachedOutline = false;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    titleController.removeListener(_handleTitleChanged);
    outlineController.removeListener(_syncMainOutlineToDetached);
    _detachedOutlineController.removeListener(_scheduleDetachedOutlineSync);
    _outlineSyncTimer?.cancel();
    // Autosave 只监听主 controller；dispose 前必须 flush debounce，否则丢最后一次输入。
    _syncDetachedOutlineToMain();
    _disposed = true;

    await _window.dispose();
    _detachedOutlineController.dispose();
  }
}

class ChapterOutlineWindowAnchor extends StatelessWidget {
  const ChapterOutlineWindowAnchor({
    super.key,
    required this.session,
    required this.child,
  });

  final ChapterOutlineWindowSession session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DetachedWindowAnchor(
      session: session._window,
      builder: (context) => _ChapterOutlineWindowPage(
        session: session,
        appearance: session._appearance,
      ),
      child: child,
    );
  }
}

class _ChapterOutlineWindowPage extends StatefulWidget {
  const _ChapterOutlineWindowPage({
    required this.session,
    required this.appearance,
  });

  final ChapterOutlineWindowSession session;
  final ChapterOutlineWindowAppearance appearance;

  @override
  State<_ChapterOutlineWindowPage> createState() =>
      _ChapterOutlineWindowPageState();
}

class _ChapterOutlineWindowPageState extends State<_ChapterOutlineWindowPage> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final appearance = widget.appearance;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: DesktopWindowFrame(
        showCustomTitleBar: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x3l,
            RevericSpacing.x2l,
            RevericSpacing.x3l,
            RevericSpacing.x3l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.session.titleController,
                builder: (context, titleValue, child) {
                  return Text(
                    titleValue.text.isEmpty
                        ? context.t(LocaleKeys.workspaceChapterOutline)
                        : titleValue.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RevericTheme.typographyOf(
                      context,
                    ).heading2.copyWith(color: colors.textPrimary),
                  );
                },
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.workspaceChapterOutline),
                style: RevericTheme.typographyOf(
                  context,
                ).ui.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              Expanded(
                child: RevericMarkdownEditor(
                  controller: widget.session._detachedOutlineController,
                  focusNode: _focusNode,
                  hintText: context.t(LocaleKeys.workspaceOutlineContentHint),
                  fontFamily: appearance.fontFamily,
                  fontSize: appearance.fontSize,
                  letterSpacing: appearance.letterSpacing,
                  lineHeight: appearance.lineHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
