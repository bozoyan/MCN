// 职责: 阅读模式正文渲染 — 以单章滚动、连续章节流或单屏横向分页展示已格式化正文。
// 关联文件:
//   lib/shared/widgets/reading/reading_chapter_loading_placeholder.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/utils/chapter_text_formatter.dart
//   lib/shared/models/chapter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/reading.json
//   assets/translations/zh-CN/reading.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/chapter.dart';
import '../../providers/novel_providers.dart';
import '../../utils/chapter_text_formatter.dart';
import 'chapter_title.dart';
import 'reading_chapter_loading_placeholder.dart';
import 'reading_theme_palette.dart';

/// 阅读正文的渲染行为。
enum ReadingContentMode { scroll, horizontal_page }

/// 阅读模式正文视图。
///
/// 调用方负责提供已格式化的章节正文与阅读偏好。本组件不会写入章节内容，
/// 仅在当前章节读完时通过 [onChapterEnd] 通知调用方切换章节。
class ReadingContentView extends StatelessWidget {
  const ReadingContentView({
    super.key,
    required this.chapterTitle,
    required this.chapterBody,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.horizontalMargin,
    required this.bold,
    required this.mode,
    this.scrollController,
    this.onScrollOffsetChanged,
    this.onChapterEnd,
    this.onPageChanged,
    this.initialScrollOffset = 0,
    this.initialPage = 0,
    this.showScrollbar = true,
  });

  final String chapterTitle;
  final String chapterBody;
  final ReadingPalette palette;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final double paragraphSpacing;
  final double horizontalMargin;
  final bool bold;
  final ReadingContentMode mode;
  final ScrollController? scrollController;
  final ValueChanged<double>? onScrollOffsetChanged;
  final VoidCallback? onChapterEnd;
  final ValueChanged<int>? onPageChanged;
  final double initialScrollOffset;
  final int initialPage;
  final bool showScrollbar;

  @override
  Widget build(BuildContext context) {
    final paragraphs = _splitParagraphs(chapterBody);
    final styles = _ReadingTextStyles(
      palette: palette,
      fontFamily: fontFamily,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
      bold: bold,
    );

    return ColoredBox(
      color: palette.background,
      child: switch (mode) {
        ReadingContentMode.scroll => _ScrollContentView(
          chapterTitle: chapterTitle,
          paragraphs: paragraphs,
          styles: styles,
          horizontalMargin: horizontalMargin,
          scrollController: scrollController,
          onScrollOffsetChanged: onScrollOffsetChanged,
          onChapterEnd: onChapterEnd,
          initialScrollOffset: initialScrollOffset,
          showScrollbar: showScrollbar,
        ),
        ReadingContentMode.horizontal_page => _HorizontalPageContentView(
          chapterTitle: chapterTitle,
          paragraphs: paragraphs,
          styles: styles,
          horizontalMargin: horizontalMargin,
          onChapterEnd: onChapterEnd,
          onPageChanged: onPageChanged,
          initialPage: initialPage,
        ),
      },
    );
  }

  /// 保留格式化后的全角段首缩进，只清理普通空格与 tab 的行首尾噪声。
  static List<String> _splitParagraphs(String body) {
    if (body.trim().isEmpty) {
      return const [];
    }
    return body
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceAll(RegExp(r'^[\t ]+|[\t ]+$'), ''))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

class _ReadingTextStyles {
  const _ReadingTextStyles({
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.bold,
  });

  final ReadingPalette palette;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final double paragraphSpacing;
  final bool bold;

  TextStyle get body => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize.toDouble(),
    letterSpacing: letterSpacing,
    height: lineHeight,
    color: palette.textPrimary,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    decoration: TextDecoration.none,
  );

  TextStyle get title => TextStyle(
    fontFamily: fontFamily,
    fontSize: (fontSize + 6).toDouble(),
    height: 1.3,
    color: palette.chapterTitle,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  double get paragraphGap => fontSize * lineHeight * paragraphSpacing;
  double get titleGap => fontSize * lineHeight * 1.2;
  double get topPadding => fontSize * 2.0;
  double get bottomPadding => fontSize * 4.0;
}

/// 连续章节流中单章正文的展示单元。
class ReadingChapterText extends StatelessWidget {
  const ReadingChapterText({
    super.key,
    required this.chapterTitle,
    required this.chapterBody,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.bold,
    required this.padding,
  });

  final String chapterTitle;
  final String chapterBody;
  final ReadingPalette palette;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final double paragraphSpacing;
  final bool bold;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final styles = _ReadingTextStyles(
      palette: palette,
      fontFamily: fontFamily,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
      bold: bold,
    );
    return Padding(
      padding: padding,
      child: _ParagraphsLayout(
        chapterTitle: chapterTitle,
        paragraphs: ReadingContentView._splitParagraphs(chapterBody),
        styles: styles,
      ),
    );
  }
}

class _ParagraphsLayout extends StatelessWidget {
  const _ParagraphsLayout({
    required this.chapterTitle,
    required this.paragraphs,
    required this.styles,
  });

  final String chapterTitle;
  final List<String> paragraphs;
  final _ReadingTextStyles styles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapterTitle.isNotEmpty) ...[
          Text(chapterTitle, style: styles.title),
          SizedBox(height: styles.titleGap),
        ],
        if (paragraphs.isEmpty)
          Text(
            context.t(LocaleKeys.readingNoContent),
            style: styles.body.copyWith(color: styles.palette.textSecondary),
          )
        else
          ...paragraphs.expand((paragraph) sync* {
            yield Text(paragraph, style: styles.body);
            yield SizedBox(height: styles.paragraphGap);
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 连续章节流
// ---------------------------------------------------------------------------

/// 连续滚动阅读的虚拟章节流。
///
/// 当前章节作为滚动锚点，前后章节分别由 [CustomScrollView] 的两个 sliver
/// 延展。列表只构建可见范围附近的章节，既能向上回看，也不会一次渲染整本书。
///
/// 章节从加载骨架换成正文、或被回收后重新加载时高度会变化；位于锚点章节
/// 与正在读的章节之间的章节变高会把正文推走，因此每次章节尺寸变化后都按
/// 高度差把滚动位置补回去。
class ReadingContinuousChapterStream extends ConsumerStatefulWidget {
  const ReadingContinuousChapterStream({
    super.key,
    required this.databasePath,
    required this.chapters,
    required this.initialChapterIndex,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.horizontalMargin,
    required this.bold,
    required this.onActiveChapterChanged,
    this.onChapterProgressChanged,
    this.initialScrollOffset = 0,
  });

  final String databasePath;
  final List<Chapter> chapters;
  final int initialChapterIndex;
  final ReadingPalette palette;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final double paragraphSpacing;
  final double horizontalMargin;
  final bool bold;
  final ValueChanged<String> onActiveChapterChanged;
  final void Function(String chapterId, double scrollOffset)?
  onChapterProgressChanged;
  final double initialScrollOffset;

  @override
  ConsumerState<ReadingContinuousChapterStream> createState() =>
      _ReadingContinuousChapterStreamState();
}

class _ReadingContinuousChapterStreamState
    extends ConsumerState<ReadingContinuousChapterStream> {
  final _scrollController = ScrollController();
  final _anchorKey = GlobalKey();
  final _chapterKeys = <String, GlobalKey>{};
  final _loadedChapterIds = <String>{};

  /// 已加载过的正文。章节滑出缓存范围后 provider 会释放，重新进入时直接用
  /// 这份正文渲染，不再闪回加载骨架、也不会再改变一次高度。
  final _chapterCache = <String, Chapter>{};
  String? _lastReportedChapterId;

  /// 需要保持不动的章节，以及上一次记录的各已构建章节高度。
  String? _readingAnchorId;
  final _chapterHeights = <String, double>{};
  var _anchorCorrectionPending = false;
  var _restoredInitial = false;
  var _reportScheduled = false;
  var _restoreAttempts = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreInitialOffset();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    _scheduleChapterPositionReport();
  }

  void _restoreInitialOffset() {
    if (_restoredInitial || !_scrollController.hasClients) {
      return;
    }
    final initialChapterId = _initialChapterId;
    if (!_loadedChapterIds.contains(initialChapterId)) {
      return;
    }

    final readerBox = context.findRenderObject() as RenderBox?;
    final chapterBox =
        _keyFor(initialChapterId).currentContext?.findRenderObject()
            as RenderBox?;
    if (readerBox == null ||
        chapterBox == null ||
        !chapterBox.attached ||
        chapterBox.size.height <= 0) {
      _retryInitialRestore();
      return;
    }

    final readerTop = readerBox.localToGlobal(Offset.zero).dy;
    final chapterTop = chapterBox.localToGlobal(Offset.zero).dy;
    final currentChapterOffset = (readerTop - chapterTop).clamp(
      0.0,
      chapterBox.size.height,
    );
    final targetChapterOffset = widget.initialScrollOffset.clamp(
      0.0,
      (chapterBox.size.height - 1).clamp(0.0, double.infinity),
    );
    final targetScrollOffset =
        _scrollController.offset + targetChapterOffset - currentChapterOffset;
    final position = _scrollController.position;
    final clampedTarget = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clampedTarget - _scrollController.offset).abs() >= 1) {
      _scrollController.jumpTo(clampedTarget);
    }
    _restoredInitial = true;
    _scheduleChapterPositionReport();
  }

  String get _initialChapterId {
    final index = widget.initialChapterIndex
        .clamp(0, widget.chapters.length - 1)
        .toInt();
    return widget.chapters[index].id;
  }

  void _retryInitialRestore() {
    if (_restoreAttempts >= 3) {
      _restoredInitial = true;
      _scheduleChapterPositionReport();
      return;
    }
    _restoreAttempts += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restoreInitialOffset();
      }
    });
  }

  GlobalKey _keyFor(String chapterId) {
    return _chapterKeys.putIfAbsent(chapterId, GlobalKey.new);
  }

  bool _handleScrollEnd(ScrollEndNotification notification) {
    _scheduleChapterPositionReport();
    return false;
  }

  void _scheduleChapterPositionReport() {
    if (_reportScheduled) {
      return;
    }
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (mounted) {
        _reportChapterPosition();
      }
    });
  }

  void _reportChapterPosition() {
    if (_anchorCorrectionPending) {
      _anchorCorrectionPending = false;
      // 校正会触发滚动监听并在下一帧重新上报，这一帧的布局已经过时。
      if (_correctReadingAnchor()) {
        return;
      }
    }
    final position = _chapterPositionAtViewportTop();
    if (position == null) {
      return;
    }
    if (_restoredInitial) {
      _captureReadingAnchor();
    }
    if (position.chapterId != _lastReportedChapterId) {
      _lastReportedChapterId = position.chapterId;
      widget.onActiveChapterChanged(position.chapterId);
    }
    widget.onChapterProgressChanged?.call(
      position.chapterId,
      position.scrollOffset,
    );
  }

  bool _handleChapterSizeChanged(SizeChangedLayoutNotification notification) {
    _anchorCorrectionPending = true;
    _scheduleChapterPositionReport();
    return true;
  }

  /// 抵消锚点章节之前内容的高度变化；返回是否发生了跳转。
  ///
  /// 被推远的章节可能已超出缓存范围而被回收，无法直接量它的新位置，所以按
  /// 变化章节自身的高度差计算：滚动锚点之后的章节向下生长，排在正在读的
  /// 章节之前时把它往下推；滚动锚点之前的章节向上生长，排在它之后（含它
  /// 自身）时把它的顶边往上推。
  bool _correctReadingAnchor() {
    final anchorId = _readingAnchorId;
    if (anchorId == null || !_scrollController.hasClients) {
      return false;
    }
    final readingIndex = widget.chapters.indexWhere((c) => c.id == anchorId);
    if (readingIndex < 0) {
      return false;
    }
    final centerIndex = _centerIndex;
    var drift = 0.0;
    final range = readingIndex >= centerIndex
        ? (start: centerIndex, end: readingIndex, sign: 1.0)
        : (start: readingIndex, end: centerIndex, sign: -1.0);
    for (var index = range.start; index < range.end; index++) {
      final chapterId = widget.chapters[index].id;
      final oldHeight = _chapterHeights[chapterId];
      final newHeight = _chapterHeight(chapterId);
      if (oldHeight == null || newHeight == null) {
        continue;
      }
      drift += range.sign * (newHeight - oldHeight);
    }
    _recordChapterHeights();
    if (drift.abs() < 1) {
      return false;
    }
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + drift).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    return true;
  }

  /// 优先取视口内最后一个露出顶边的章节：它之前的骨架章节加载变高时，
  /// 正在读的正文仍留在原处；视口内没有章节顶边时取覆盖视口顶部的章节。
  void _captureReadingAnchor() {
    _recordChapterHeights();
    final readerBox = context.findRenderObject() as RenderBox?;
    if (readerBox == null) {
      return;
    }
    final readerTop = readerBox.localToGlobal(Offset.zero).dy;
    final viewportHeight = readerBox.size.height;
    String? anchorId;
    double? anchorTop;
    var anchorTopVisible = false;
    for (final entry in _chapterKeys.entries) {
      final chapterBox =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (chapterBox == null || !chapterBox.attached) {
        continue;
      }
      final chapterTop = chapterBox.localToGlobal(Offset.zero).dy - readerTop;
      final topVisible = chapterTop >= 0 && chapterTop < viewportHeight;
      final coversTop =
          chapterTop < 0 && chapterTop + chapterBox.size.height > 0;
      if (topVisible && (!anchorTopVisible || chapterTop > anchorTop!)) {
        anchorId = entry.key;
        anchorTop = chapterTop;
        anchorTopVisible = true;
      } else if (coversTop && !anchorTopVisible) {
        anchorId = entry.key;
        anchorTop = chapterTop;
      }
    }
    _readingAnchorId = anchorId;
  }

  void _recordChapterHeights() {
    _chapterHeights.clear();
    for (final chapterId in _chapterKeys.keys) {
      final height = _chapterHeight(chapterId);
      if (height != null) {
        _chapterHeights[chapterId] = height;
      }
    }
  }

  double? _chapterHeight(String chapterId) {
    final chapterBox =
        _chapterKeys[chapterId]?.currentContext?.findRenderObject()
            as RenderBox?;
    if (chapterBox == null || !chapterBox.attached || !chapterBox.hasSize) {
      return null;
    }
    return chapterBox.size.height;
  }

  int get _centerIndex =>
      widget.initialChapterIndex.clamp(0, widget.chapters.length - 1).toInt();

  ({String chapterId, double scrollOffset})? _chapterPositionAtViewportTop() {
    final readerBox = context.findRenderObject() as RenderBox?;
    if (readerBox == null) {
      return null;
    }
    final top = readerBox.localToGlobal(Offset.zero).dy + 1;
    String? nearestChapterId;
    var nearestDistance = double.infinity;

    for (final entry in _chapterKeys.entries) {
      final chapterBox =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (chapterBox == null || !chapterBox.attached) {
        continue;
      }
      final chapterTop = chapterBox.localToGlobal(Offset.zero).dy;
      final chapterBottom = chapterTop + chapterBox.size.height;
      if (chapterTop <= top && chapterBottom > top) {
        return (
          chapterId: entry.key,
          scrollOffset: (top - chapterTop).clamp(0.0, chapterBox.size.height),
        );
      }
      if (chapterTop > top && chapterTop - top < nearestDistance) {
        nearestChapterId = entry.key;
        nearestDistance = chapterTop - top;
      }
    }

    if (nearestChapterId == null) {
      return null;
    }
    return (chapterId: nearestChapterId, scrollOffset: 0);
  }

  void _handleChapterContentReady(String chapterId, Chapter? chapter) {
    if (chapter != null) {
      _chapterCache[chapterId] = chapter;
    }
    if (!_loadedChapterIds.add(chapterId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (chapterId == _initialChapterId) {
        _restoreInitialOffset();
      }
      _scheduleChapterPositionReport();
    });
  }

  Widget _buildChapter(int index) {
    final chapter = widget.chapters[index];
    return _ReadingStreamChapter(
      key: _keyFor(chapter.id),
      databasePath: widget.databasePath,
      chapterId: chapter.id,
      title: readingChapterTitle(context, chapter),
      palette: widget.palette,
      fontFamily: widget.fontFamily,
      fontSize: widget.fontSize,
      letterSpacing: widget.letterSpacing,
      lineHeight: widget.lineHeight,
      paragraphSpacing: widget.paragraphSpacing,
      horizontalMargin: widget.horizontalMargin,
      bold: widget.bold,
      cachedChapter: _chapterCache[chapter.id],
      onContentReady: _handleChapterContentReady,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapters.isEmpty) {
      return const SizedBox.shrink();
    }
    final anchorIndex = widget.initialChapterIndex
        .clamp(0, widget.chapters.length - 1)
        .toInt();

    return NotificationListener<ScrollEndNotification>(
      onNotification: _handleScrollEnd,
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: _handleChapterSizeChanged,
        child: CustomScrollView(
          controller: _scrollController,
          center: _anchorKey,
          anchor: 0,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
          slivers: [
            if (anchorIndex > 0)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildChapter(anchorIndex - index - 1),
                  childCount: anchorIndex,
                ),
              ),
            SliverToBoxAdapter(key: _anchorKey, child: const SizedBox.shrink()),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildChapter(anchorIndex + index),
                childCount: widget.chapters.length - anchorIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingStreamChapter extends ConsumerWidget {
  const _ReadingStreamChapter({
    super.key,
    required this.databasePath,
    required this.chapterId,
    required this.title,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.horizontalMargin,
    required this.bold,
    required this.cachedChapter,
    required this.onContentReady,
  });

  final String databasePath;
  final String chapterId;

  /// 取自章节树条目：正文详情直查原表，不带章号。
  final String title;
  final ReadingPalette palette;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final double paragraphSpacing;
  final double horizontalMargin;
  final bool bold;
  final Chapter? cachedChapter;
  final void Function(String chapterId, Chapter? chapter) onContentReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterAsync = ref.watch(
      chapterContentByIdProvider(path: databasePath, chapterId: chapterId),
    );
    final padding = EdgeInsets.fromLTRB(
      horizontalMargin,
      fontSize * 2.0,
      horizontalMargin,
      fontSize * 4.0,
    );
    Widget chapterText(String state, String body) => ReadingChapterText(
      key: ValueKey('reading-chapter-$state-$chapterId'),
      chapterTitle: title,
      chapterBody: body,
      palette: palette,
      fontFamily: fontFamily,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
      bold: bold,
      padding: padding,
    );
    return SizeChangedLayoutNotifier(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: chapterAsync.when(
          data: (chapter) {
            onContentReady(chapterId, chapter);
            if (chapter == null) {
              return chapterText('empty', '');
            }
            return chapterText('content', formatText(chapter.content));
          },
          loading: () => switch (cachedChapter) {
            final cached? => chapterText('content', formatText(cached.content)),
            null => ReadingChapterLoadingPlaceholder(
              key: ValueKey('reading-chapter-loading-$chapterId'),
              padding: padding,
              palette: palette,
              fontSize: fontSize,
              lineHeight: lineHeight,
            ),
          },
          error: (_, _) {
            onContentReady(chapterId, null);
            return chapterText('error', '');
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 垂直滚动
// ---------------------------------------------------------------------------

class _ScrollContentView extends StatefulWidget {
  const _ScrollContentView({
    required this.chapterTitle,
    required this.paragraphs,
    required this.styles,
    required this.horizontalMargin,
    required this.scrollController,
    required this.onScrollOffsetChanged,
    required this.onChapterEnd,
    required this.initialScrollOffset,
    required this.showScrollbar,
  });

  final String chapterTitle;
  final List<String> paragraphs;
  final _ReadingTextStyles styles;
  final double horizontalMargin;
  final ScrollController? scrollController;
  final ValueChanged<double>? onScrollOffsetChanged;
  final VoidCallback? onChapterEnd;
  final double initialScrollOffset;
  final bool showScrollbar;

  @override
  State<_ScrollContentView> createState() => _ScrollContentViewState();
}

class _ScrollContentViewState extends State<_ScrollContentView> {
  late final ScrollController _controller;
  late final bool _ownsController;
  var _restoredInitial = false;
  var _requestedChapterEnd = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.scrollController == null;
    _controller = widget.scrollController ?? ScrollController();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreInitialOffset(),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleScroll() {
    if (!_controller.hasClients) {
      return;
    }
    widget.onScrollOffsetChanged?.call(_controller.offset);

    final position = _controller.position;
    if (_requestedChapterEnd ||
        widget.onChapterEnd == null ||
        position.maxScrollExtent <= 0 ||
        position.extentAfter > 1) {
      return;
    }
    _requestChapterEnd();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.overscroll > 0 &&
        notification.metrics.extentAfter <= 1) {
      _requestChapterEnd();
    }
    return false;
  }

  void _requestChapterEnd() {
    if (_requestedChapterEnd || widget.onChapterEnd == null) {
      return;
    }
    _requestedChapterEnd = true;
    widget.onChapterEnd?.call();
  }

  void _restoreInitialOffset() {
    if (_restoredInitial || !_controller.hasClients) {
      return;
    }
    final maxExtent = _controller.position.maxScrollExtent;
    // 内容尚未布局完成（maxScrollExtent 仍为 0）但需要恢复非零偏移时，
    // 延迟到下一帧重试，避免过早标记为已恢复。
    if (widget.initialScrollOffset > 0 && maxExtent <= 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreInitialOffset(),
      );
      return;
    }
    final target = widget.initialScrollOffset.clamp(0.0, maxExtent);
    if (target > 0) {
      _controller.jumpTo(target);
    }
    _restoredInitial = true;
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(
        widget.horizontalMargin,
        widget.styles.topPadding,
        widget.horizontalMargin,
        widget.styles.bottomPadding,
      ),
      child: _ParagraphsLayout(
        chapterTitle: widget.chapterTitle,
        paragraphs: widget.paragraphs,
        styles: widget.styles,
      ),
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: widget.showScrollbar
          ? Scrollbar(controller: _controller, child: scrollView)
          : scrollView,
    );
  }
}

// ---------------------------------------------------------------------------
// 单屏横向分页
// ---------------------------------------------------------------------------

class _HorizontalPageContentView extends StatefulWidget {
  const _HorizontalPageContentView({
    required this.chapterTitle,
    required this.paragraphs,
    required this.styles,
    required this.horizontalMargin,
    required this.onChapterEnd,
    required this.onPageChanged,
    required this.initialPage,
  });

  final String chapterTitle;
  final List<String> paragraphs;
  final _ReadingTextStyles styles;
  final double horizontalMargin;
  final VoidCallback? onChapterEnd;
  final ValueChanged<int>? onPageChanged;
  final int initialPage;

  @override
  State<_HorizontalPageContentView> createState() =>
      _HorizontalPageContentViewState();
}

class _HorizontalPageContentViewState
    extends State<_HorizontalPageContentView> {
  late final PageController _pageController;
  var _requestingChapterEnd = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage);
    _pageController.addListener(_reportPageChanged);
  }

  @override
  void dispose() {
    _pageController.removeListener(_reportPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _reportPageChanged() {
    if (!_pageController.hasClients || widget.onPageChanged == null) {
      return;
    }
    final page = _pageController.page?.round();
    if (page != null) {
      widget.onPageChanged?.call(page);
    }
  }

  void _goPrevious() {
    if (!_pageController.hasClients || _pageController.page! <= 0) {
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _goNext(int pageCount) {
    if (!_pageController.hasClients) {
      return;
    }
    final currentPage = _pageController.page!.round();
    if (currentPage < pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (_requestingChapterEnd || widget.onChapterEnd == null) {
      return;
    }
    _requestingChapterEnd = true;
    widget.onChapterEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pages = _paginate(
          context,
          constraints: constraints,
          chapterTitle: widget.chapterTitle,
          paragraphs: widget.paragraphs,
          styles: widget.styles,
          horizontalMargin: widget.horizontalMargin,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (details.localPosition.dx < constraints.maxWidth * 0.35) {
              _goPrevious();
            } else if (details.localPosition.dx > constraints.maxWidth * 0.65) {
              _goNext(pages.length);
            }
          },
          child: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              return ClipRect(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.horizontalMargin,
                    widget.styles.topPadding,
                    widget.horizontalMargin,
                    widget.styles.bottomPadding,
                  ),
                  child: _ParagraphsLayout(
                    chapterTitle: pages[index].chapterTitle,
                    paragraphs: pages[index].paragraphs,
                    styles: widget.styles,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ReadingPage {
  const _ReadingPage({required this.chapterTitle, required this.paragraphs});

  final String chapterTitle;
  final List<String> paragraphs;
}

List<_ReadingPage> _paginate(
  BuildContext context, {
  required BoxConstraints constraints,
  required String chapterTitle,
  required List<String> paragraphs,
  required _ReadingTextStyles styles,
  required double horizontalMargin,
}) {
  if (paragraphs.isEmpty) {
    return [_ReadingPage(chapterTitle: chapterTitle, paragraphs: const [])];
  }

  final maxWidth = (constraints.maxWidth - horizontalMargin * 2)
      .clamp(1.0, double.infinity)
      .toDouble();
  final pageHeight =
      (constraints.maxHeight - styles.topPadding - styles.bottomPadding)
          .clamp(1.0, double.infinity)
          .toDouble();
  final textScaler = MediaQuery.textScalerOf(context);
  final titleHeight = chapterTitle.isEmpty
      ? 0.0
      : _measureHeight(
              chapterTitle,
              width: maxWidth,
              style: styles.title,
              textScaler: textScaler,
              textDirection: Directionality.of(context),
            ) +
            styles.titleGap;

  final pages = <_ReadingPage>[];
  var pageTitle = chapterTitle;
  var pageParagraphs = <String>[];
  var remainingHeight = (pageHeight - titleHeight).clamp(1.0, pageHeight);

  void commitPage() {
    pages.add(
      _ReadingPage(
        chapterTitle: pageTitle,
        paragraphs: List.unmodifiable(pageParagraphs),
      ),
    );
    pageTitle = '';
    pageParagraphs = <String>[];
    remainingHeight = pageHeight;
  }

  for (final paragraph in paragraphs) {
    var remainingParagraph = paragraph;
    while (remainingParagraph.isNotEmpty) {
      final gap = pageParagraphs.isEmpty ? 0.0 : styles.paragraphGap;
      final paragraphHeight = _measureHeight(
        remainingParagraph,
        width: maxWidth,
        style: styles.body,
        textScaler: textScaler,
        textDirection: Directionality.of(context),
      );
      if (paragraphHeight + gap <= remainingHeight) {
        pageParagraphs.add(remainingParagraph);
        remainingHeight -= paragraphHeight + gap;
        break;
      }

      final availableForText = remainingHeight - gap;
      if (availableForText > styles.body.fontSize!) {
        final split = _splitTextToHeight(
          remainingParagraph,
          width: maxWidth,
          height: availableForText,
          style: styles.body,
          textScaler: textScaler,
          textDirection: Directionality.of(context),
        );
        if (split.$1.isNotEmpty) {
          pageParagraphs.add(split.$1);
          remainingParagraph = split.$2;
        }
      }

      if (pageParagraphs.isNotEmpty || pageTitle.isNotEmpty) {
        commitPage();
        continue;
      }

      final split = _splitTextToHeight(
        remainingParagraph,
        width: maxWidth,
        height: pageHeight,
        style: styles.body,
        textScaler: textScaler,
        textDirection: Directionality.of(context),
      );
      pageParagraphs.add(split.$1.isEmpty ? remainingParagraph : split.$1);
      remainingParagraph = split.$1.isEmpty ? '' : split.$2;
      commitPage();
    }
  }

  if (pageParagraphs.isNotEmpty || pageTitle.isNotEmpty) {
    commitPage();
  }
  return pages;
}

double _measureHeight(
  String text, {
  required double width,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: width);
  return painter.height;
}

(String, String) _splitTextToHeight(
  String text, {
  required double width,
  required double height,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: width);
  var occupiedHeight = 0.0;
  for (final line in painter.computeLineMetrics()) {
    if (occupiedHeight + line.height > height && occupiedHeight > 0) {
      break;
    }
    occupiedHeight += line.height;
    if (occupiedHeight >= height) {
      break;
    }
  }
  if (occupiedHeight <= 0) {
    return ('', text);
  }
  final endIndex = painter
      .getPositionForOffset(Offset(width, occupiedHeight - 0.1))
      .offset;
  if (endIndex <= 0 || endIndex >= text.length) {
    return (text, '');
  }
  return (text.substring(0, endIndex).trimRight(), text.substring(endIndex));
}
