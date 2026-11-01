// 职责: 移动端沉浸式阅读页 — 格式化正文、自动续读、目录 Bottom Sheet、按需显示阅读控制、上下或横向翻页、阅读设置 bottom sheet、进度持久化。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/mobile/pages/library_page.dart
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/utils/chapter_text_formatter.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/reading_progress_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   lib/shared/components/fullscreen_system_ui.dart
//   lib/shared/components/fullscreen_system_ui_bottom_sheet.dart
//   lib/shared/services/system_ui_service.dart
//   pubspec.yaml
//   assets/translations/en/reading.json
//   assets/translations/zh-CN/reading.json
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/widgets/novel_open_boundary.dart';
import '../../../shared/components/fullscreen_system_ui.dart';
import '../../../shared/components/fullscreen_system_ui_bottom_sheet.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/chapter.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/reading_progress_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/services/system_ui_service.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/chapter_text_formatter.dart';
import '../../../shared/widgets/reading/reading_content_view.dart';
import '../../../shared/widgets/reading/chapter_title.dart';
import '../../../shared/widgets/reading/reading_settings_controls.dart';
import '../../../shared/widgets/reading/reading_theme_palette.dart';

const _readingTocItemExtent = RevericSizes.buttonHeight + RevericSpacing.x4l;
const _minimumReadingBrightness = 0.35;
const _readingContextBarHeight =
    RevericSizes.buttonHeight + RevericSpacing.xs;
const _readingFooterReservedHeight = RevericSizes.buttonHeight;

final _log = AppLogger.forModule('MobileReading');

/// 移动端阅读页：纯阅读体验，无编辑、无 AI。
class MobileReadingPage extends HookConsumerWidget {
  const MobileReadingPage({
    super.key,
    required this.novelId,
    required this.novelTitle,
    required this.databasePath,
  });

  final String novelId;
  final String novelTitle;
  final String databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovelOpenBoundary(
      novelId: novelId,
      child: HookConsumer(
        builder: (context, ref, _) => _buildContent(context, ref),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final typo = RevericTheme.typographyOf(context);
    final systemUi = ref.read(systemUiServiceProvider);

    final fontFamily = ref.watch(readingFontFamilyProvider);
    final fontSize = ref.watch(readingFontSizeProvider);
    final letterSpacing = ref.watch(readingLetterSpacingProvider);
    final lineHeight = ref.watch(readingLineHeightProvider);
    final paragraphSpacing = ref.watch(readingParagraphSpacingProvider);
    final margin = ref.watch(readingMarginProvider);
    final bold = ref.watch(readingBoldProvider);
    final backgroundTheme = ref.watch(readingBackgroundThemeProvider);
    final readingMode = ref.watch(mobileReadingModeProvider);
    final palette = ReadingPalette.of(backgroundTheme);

    final chaptersAsync = ref.watch(chapterTreeProvider(databasePath));
    final readableChapters =
        chaptersAsync.value?.where((chapter) => chapter.isChapter).toList() ??
        const <Chapter>[];
    final isChapterTreeLoading =
        chaptersAsync.isLoading && !chaptersAsync.hasValue;
    final hasChapterTreeError = chaptersAsync.hasError;

    final progressAsync = ref.watch(novelReadingProgressProvider(novelId));
    final progress = progressAsync.value;

    final currentChapterId = useState<String?>(progress?.chapterId);
    final continuousAnchorChapterId = useState<String?>(progress?.chapterId);
    final controlsVisible = useValueNotifier(false);
    final readingBrightness = useValueNotifier(1.0);
    final lastSavedOffset = useRef<double?>(null);
    final lastContinuousProgress =
        useRef<({String chapterId, double scrollOffset})?>(null);
    final debounceTimer = useRef<Timer?>(null);
    final previousNonNightTheme = useRef(
      backgroundTheme == ReadingBackgroundTheme.night
          ? ReadingBackgroundTheme.cream
          : backgroundTheme,
    );
    final readingPointerDownPosition = useRef<Offset?>(null);
    final isReadingPointerDrag = useRef(false);

    useEffect(() {
      // 在 build 阶段捕获 notifier，dispose 时 ref 已不可用。
      final notifier = ref.read(novelReadingProgressProvider(novelId).notifier);
      return () {
        debounceTimer.value?.cancel();
        final pendingContinuousProgress = lastContinuousProgress.value;
        if (pendingContinuousProgress != null) {
          unawaited(
            notifier.setChapterProgress(
              chapterId: pendingContinuousProgress.chapterId,
              scrollOffset: pendingContinuousProgress.scrollOffset,
            ),
          );
          return;
        }
        final pendingOffset = lastSavedOffset.value;
        if (pendingOffset != null) {
          unawaited(notifier.setScrollOffset(pendingOffset));
        }
      };
    }, [novelId]);

    useEffect(() {
      final notifier = ref.read(novelReadingProgressProvider(novelId).notifier);
      final observer = _AppLifecycleObserver(
        onPaused: () {
          debounceTimer.value?.cancel();
          final pendingContinuousProgress = lastContinuousProgress.value;
          if (pendingContinuousProgress != null) {
            unawaited(
              notifier.setChapterProgress(
                chapterId: pendingContinuousProgress.chapterId,
                scrollOffset: pendingContinuousProgress.scrollOffset,
              ),
            );
            lastContinuousProgress.value = null;
            return;
          }
          final pendingOffset = lastSavedOffset.value;
          if (pendingOffset != null) {
            unawaited(notifier.setScrollOffset(pendingOffset));
            lastSavedOffset.value = null;
          }
        },
      );
      WidgetsBinding.instance.addObserver(observer);
      return () {
        WidgetsBinding.instance.removeObserver(observer);
      };
    }, [novelId]);

    void handleScrollOffset(double offset) {
      lastContinuousProgress.value = null;
      debounceTimer.value?.cancel();
      debounceTimer.value = Timer(const Duration(milliseconds: 500), () {
        if ((lastSavedOffset.value ?? -1) == offset) {
          return;
        }
        lastSavedOffset.value = offset;
        ref
            .read(novelReadingProgressProvider(novelId).notifier)
            .setScrollOffset(offset);
      });
    }

    void handleContinuousProgress(String chapterId, double offset) {
      if (currentChapterId.value != chapterId) {
        currentChapterId.value = chapterId;
      }
      final previous = lastContinuousProgress.value;
      if (previous != null &&
          previous.chapterId == chapterId &&
          (previous.scrollOffset - offset).abs() < 1) {
        return;
      }
      lastSavedOffset.value = null;
      lastContinuousProgress.value = (
        chapterId: chapterId,
        scrollOffset: offset,
      );
      debounceTimer.value?.cancel();
      debounceTimer.value = Timer(const Duration(milliseconds: 500), () {
        final pending = lastContinuousProgress.value;
        if (pending == null) {
          return;
        }
        unawaited(
          ref
              .read(novelReadingProgressProvider(novelId).notifier)
              .setChapterProgress(
                chapterId: pending.chapterId,
                scrollOffset: pending.scrollOffset,
              ),
        );
      });
    }

    // 进度恢复：仅在首次加载（chapters + progress 都就绪）时执行一次。
    final progressRestored = useRef(false);
    useEffect(() {
      if (progressRestored.value) {
        return null;
      }
      if (readableChapters.isEmpty || progress == null) {
        return null;
      }
      progressRestored.value = true;
      final preferredId = progress.chapterId ?? readableChapters.first.id;
      currentChapterId.value = preferredId;
      continuousAnchorChapterId.value = preferredId;
      if (progress.chapterId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(
            ref
                .read(novelReadingProgressProvider(novelId).notifier)
                .setChapterId(preferredId),
          );
        });
      }
      return null;
    }, [readableChapters.length, progress]);

    final selectedChapterId =
        currentChapterId.value ??
        (readableChapters.isEmpty ? null : readableChapters.first.id);
    final currentChapterAsync = selectedChapterId == null
        ? null
        : ref.watch(
            chapterContentByIdProvider(
              path: databasePath,
              chapterId: selectedChapterId,
            ),
          );
    final currentChapter = currentChapterAsync?.value;

    final currentIndex = selectedChapterId == null
        ? -1
        : readableChapters.indexWhere(
            (chapter) => chapter.id == selectedChapterId,
          );
    final currentChapterTitle =
        // 章号只在章节树条目上；正文详情直查原表不带章号。
        switch ((currentIndex >= 0 ? readableChapters[currentIndex] : null) ??
        currentChapter) {
          final chapter? => readingChapterTitle(context, chapter),
          null => novelTitle,
        };
    final nextChapterId =
        currentIndex >= 0 && currentIndex < readableChapters.length - 1
        ? readableChapters[currentIndex + 1].id
        : null;
    if (readingMode == MobileReadingMode.horizontal_page &&
        nextChapterId != null) {
      // 仅预取下一章的数据，不在后台构建正文页面。
      ref.watch(
        chapterContentByIdProvider(
          path: databasePath,
          chapterId: nextChapterId,
        ),
      );
    }

    Future<void> selectChapter(String chapterId) async {
      // 取消待写的上一章滚动偏移，防止 debounce 回调把旧偏移写入新章节。
      debounceTimer.value?.cancel();
      lastSavedOffset.value = null;
      lastContinuousProgress.value = null;
      if (readingMode == MobileReadingMode.vertical_scroll) {
        continuousAnchorChapterId.value = chapterId;
      }
      currentChapterId.value = chapterId;
      await ref
          .read(novelReadingProgressProvider(novelId).notifier)
          .setChapterId(chapterId);
    }

    void updateContinuousChapter(String chapterId) {
      if (currentChapterId.value == chapterId) {
        return;
      }
      debounceTimer.value?.cancel();
      lastSavedOffset.value = null;
      lastContinuousProgress.value = null;
      currentChapterId.value = chapterId;
    }

    Future<void> goNext() async {
      if (currentIndex < 0 || currentIndex >= readableChapters.length - 1) {
        return;
      }
      await selectChapter(readableChapters[currentIndex + 1].id);
    }

    Future<void> toggleNightMode() async {
      final notifier = ref.read(appSettingsProvider.notifier);
      if (backgroundTheme == ReadingBackgroundTheme.night) {
        await notifier.setReadingBackgroundTheme(previousNonNightTheme.value);
        return;
      }
      previousNonNightTheme.value = backgroundTheme;
      await notifier.setReadingBackgroundTheme(ReadingBackgroundTheme.night);
    }

    Future<void> openTocSheet() async {
      final chapterId = await _openTocSheet(
        context: context,
        systemUi: systemUi,
        novelTitle: novelTitle,
        chapters: readableChapters,
        currentChapterId: currentChapterId.value,
        palette: palette,
      );
      if (!context.mounted || chapterId == null) {
        return;
      }
      await selectChapter(chapterId);
      controlsVisible.value = false;
    }

    final systemUiOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: palette.isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: palette.iconBrightness,
      systemNavigationBarColor: palette.background,
      systemNavigationBarIconBrightness: palette.iconBrightness,
    );

    final continuousAnchorIndex = readableChapters.indexWhere(
      (chapter) =>
          chapter.id == (continuousAnchorChapterId.value ?? selectedChapterId),
    );

    final initialOffset = progress?.chapterId == selectedChapterId
        ? progress?.scrollOffset ?? 0.0
        : 0.0;
    final initialPage = progress?.chapterId == selectedChapterId
        ? (progress?.scrollOffset ?? 0).toInt()
        : 0;

    return FullscreenSystemUi(
      overlayStyle: systemUiOverlayStyle,
      child: Scaffold(
        key: const ValueKey('reading-page-scaffold'),
        backgroundColor: palette.background,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (isChapterTreeLoading)
                Center(
                  child: CircularProgressIndicator(color: palette.iconColor),
                )
              else if (hasChapterTreeError)
                _ReadingEmptyState(
                  palette: palette,
                  typo: typo,
                  message: context.t(LocaleKeys.commonLoadFailed),
                  description: '',
                )
              else if (readableChapters.isEmpty)
                _ReadingEmptyState(
                  palette: palette,
                  typo: typo,
                  message: context.t(LocaleKeys.readingNoChapters),
                  description: context.t(
                    LocaleKeys.readingNoChaptersDescription,
                  ),
                )
              else if (readingMode != MobileReadingMode.vertical_scroll &&
                  currentChapter == null)
                if (currentChapterAsync?.isLoading ?? false)
                  Center(
                    child: CircularProgressIndicator(color: palette.iconColor),
                  )
                else
                  _ReadingEmptyState(
                    palette: palette,
                    typo: typo,
                    message: context.t(LocaleKeys.readingNoContent),
                    description: '',
                  )
              else
                Padding(
                  padding: const EdgeInsets.only(
                    top: _readingContextBarHeight,
                    bottom: _readingFooterReservedHeight,
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      readingPointerDownPosition.value = event.localPosition;
                      isReadingPointerDrag.value = false;
                    },
                    onPointerMove: (event) {
                      final pointerDownPosition =
                          readingPointerDownPosition.value;
                      if (pointerDownPosition == null ||
                          isReadingPointerDrag.value) {
                        return;
                      }
                      if ((event.localPosition - pointerDownPosition).distance >
                          kTouchSlop) {
                        isReadingPointerDrag.value = true;
                      }
                    },
                    onPointerUp: (event) {
                      final isTap = !isReadingPointerDrag.value;
                      readingPointerDownPosition.value = null;
                      isReadingPointerDrag.value = false;
                      if (!isTap) {
                        return;
                      }
                      final width = MediaQuery.sizeOf(context).width;
                      final isMiddleTap =
                          event.localPosition.dx >= width * 0.35 &&
                          event.localPosition.dx <= width * 0.65;
                      if (isMiddleTap) {
                        controlsVisible.value = !controlsVisible.value;
                      }
                    },
                    onPointerCancel: (_) {
                      readingPointerDownPosition.value = null;
                      isReadingPointerDrag.value = false;
                    },
                    child: readingMode == MobileReadingMode.vertical_scroll
                        ? ReadingContinuousChapterStream(
                            key: ValueKey(
                              'continuous-${continuousAnchorChapterId.value ?? selectedChapterId}',
                            ),
                            databasePath: databasePath,
                            chapters: readableChapters,
                            initialChapterIndex: continuousAnchorIndex,
                            palette: palette,
                            fontFamily: fontFamily,
                            fontSize: fontSize,
                            letterSpacing: letterSpacing,
                            lineHeight: lineHeight,
                            paragraphSpacing: paragraphSpacing,
                            horizontalMargin: margin,
                            bold: bold,
                            onActiveChapterChanged: (chapterId) {
                              updateContinuousChapter(chapterId);
                            },
                            onChapterProgressChanged: handleContinuousProgress,
                            initialScrollOffset: initialOffset,
                          )
                        : ReadingContentView(
                            key: ValueKey(
                              '$selectedChapterId-${readingMode.name}',
                            ),
                            chapterTitle: readingChapterTitle(
                              context,
                              currentIndex >= 0
                                  ? readableChapters[currentIndex]
                                  : currentChapter!,
                            ),
                            chapterBody: formatText(currentChapter!.content),
                            palette: palette,
                            fontFamily: fontFamily,
                            fontSize: fontSize,
                            letterSpacing: letterSpacing,
                            lineHeight: lineHeight,
                            paragraphSpacing: paragraphSpacing,
                            horizontalMargin: margin,
                            bold: bold,
                            mode: ReadingContentMode.horizontal_page,
                            onChapterEnd: nextChapterId == null
                                ? null
                                : () => unawaited(goNext()),
                            onPageChanged: (page) {
                              handleScrollOffset(page.toDouble());
                            },
                            initialPage: initialPage,
                          ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _ReadingContextBar(
                  chapterTitle: currentChapterTitle,
                  palette: palette,
                  typo: typo,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                left: RevericSpacing.x3l,
                right: RevericSpacing.x3l,
                bottom: RevericSpacing.sm,
                child: _ReadingStatusOverlay(palette: palette, typo: typo),
              ),
              ValueListenableBuilder<double>(
                valueListenable: readingBrightness,
                builder: (context, brightness, _) {
                  if (brightness >= 1) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: palette.textPrimary.withValues(
                          alpha: 1 - brightness,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: controlsVisible,
                    builder: (context, visible, _) {
                      if (!visible) {
                        return const SizedBox.shrink(
                          key: ValueKey('reading-controls-hidden'),
                        );
                      }
                      return ValueListenableBuilder<double>(
                        valueListenable: readingBrightness,
                        builder: (context, brightness, _) {
                          return _MobileReadingControlPanel(
                            key: const ValueKey('reading-controls'),
                            palette: palette,
                            brightness: brightness,
                            isNightMode:
                                backgroundTheme == ReadingBackgroundTheme.night,
                            canGoPrevious: currentIndex > 0,
                            canGoNext: nextChapterId != null,
                            onBrightnessChanged: (value) {
                              readingBrightness.value = value;
                            },
                            onToggleNightMode: () {
                              unawaited(toggleNightMode());
                            },
                            onOpenToc: () => unawaited(openTocSheet()),
                            onOpenSettings: () => unawaited(
                              _openSettingsSheet(context, systemUi),
                            ),
                            onPrevious: () {
                              if (currentIndex > 0) {
                                unawaited(
                                  selectChapter(
                                    readableChapters[currentIndex - 1].id,
                                  ),
                                );
                              }
                            },
                            onNext: () {
                              unawaited(goNext());
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsSheet(
    BuildContext context,
    SystemUiService systemUi,
  ) async {
    final colors = RevericTheme.colorsOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    await showFullscreenSystemUiBottomSheet<void>(
      context: context,
      systemUi: systemUi,
      backgroundColor: colors.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RevericRadius.x2l),
        ),
      ),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const _MobileReadingSettingsSheet(),
      ),
    );
  }

  Future<String?> _openTocSheet({
    required BuildContext context,
    required SystemUiService systemUi,
    required String novelTitle,
    required List<Chapter> chapters,
    required String? currentChapterId,
    required ReadingPalette palette,
  }) {
    return showFullscreenSystemUiBottomSheet<String>(
      context: context,
      systemUi: systemUi,
      backgroundColor: palette.background,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(RevericRadius.x2l),
        ),
      ),
      builder: (_) => _MobileReadingTocSheet(
        novelTitle: novelTitle,
        chapters: chapters,
        currentChapterId: currentChapterId,
        palette: palette,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 阅读状态与控制
// ---------------------------------------------------------------------------

class _ReadingContextBar extends StatelessWidget {
  const _ReadingContextBar({
    required this.chapterTitle,
    required this.palette,
    required this.typo,
    required this.onBack,
  });

  final String chapterTitle;
  final ReadingPalette palette;
  final RevericTypography typo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _readingContextBarHeight,
      color: palette.background,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x2l),
      child: Row(
        children: [
          _ReadingControlIconButton(
            icon: RevericIcons.arrow_back,
            color: palette.iconColor,
            tooltip: context.t(LocaleKeys.readingExit),
            onPressed: onBack,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              chapterTitle,
              key: const ValueKey('reading-context-title'),
              style: typo.uiMedium.copyWith(color: palette.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// 使用 StatefulWidget 管理跨前后台的 Timer 与平台 StreamSubscription，
// 让状态更新只重建底部状态栏，而不触发正文重新分页。
class _ReadingStatusOverlay extends StatefulWidget {
  const _ReadingStatusOverlay({required this.palette, required this.typo});

  final ReadingPalette palette;
  final RevericTypography typo;

  @override
  State<_ReadingStatusOverlay> createState() => _ReadingStatusOverlayState();
}

class _ReadingStatusOverlayState extends State<_ReadingStatusOverlay>
    with WidgetsBindingObserver {
  final Battery _battery = Battery();
  Timer? _statusTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  var _currentTime = DateTime.now();
  int? _batteryLevel;
  var _isRefreshing = false;
  var _isForeground = true;
  var _batteryReadFailureLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBatteryStateSubscription();
    _startStatusUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStatusUpdates();
    unawaited(_batteryStateSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _startStatusUpdates();
      return;
    }
    _isForeground = false;
    _stopStatusUpdates();
  }

  void _startBatteryStateSubscription() {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen(
      (_) => unawaited(_refreshStatus()),
      onError: _logBatteryReadFailure,
    );
  }

  void _startStatusUpdates() {
    if (!_isForeground || _statusTimer != null) {
      return;
    }
    unawaited(_refreshStatus());
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_refreshStatus());
    });
  }

  void _stopStatusUpdates() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> _refreshStatus() async {
    if (!_isForeground || _isRefreshing) {
      return;
    }
    _isRefreshing = true;
    try {
      final level = await _battery.batteryLevel;
      if (!mounted || !_isForeground) {
        return;
      }
      setState(() {
        _currentTime = DateTime.now();
        _batteryLevel = level.clamp(0, 100);
      });
    } catch (error) {
      _logBatteryReadFailure(error);
      if (mounted && _isForeground) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void _logBatteryReadFailure(Object error) {
    if (_batteryReadFailureLogged) {
      return;
    }
    _batteryReadFailureLogged = true;
    _log.warning('Battery level unavailable error=$error');
  }

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_currentTime),
      alwaysUse24HourFormat: true,
    );
    return Row(
      children: [
        Text(
          _batteryLevel == null ? '--%' : '$_batteryLevel%',
          style: widget.typo.uiSmall.copyWith(
            color: widget.palette.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          time,
          style: widget.typo.uiSmall.copyWith(
            color: widget.palette.textSecondary,
          ),
        ),
        const SizedBox(width: RevericSpacing.xs),
        RevericIcon(
          RevericIcons.battery_full,
          size: 16,
          color: widget.palette.textSecondary,
        ),
      ],
    );
  }
}

class _MobileReadingControlPanel extends StatelessWidget {
  const _MobileReadingControlPanel({
    super.key,
    required this.palette,
    required this.brightness,
    required this.isNightMode,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onBrightnessChanged,
    required this.onToggleNightMode,
    required this.onOpenToc,
    required this.onOpenSettings,
    required this.onPrevious,
    required this.onNext,
  });

  final ReadingPalette palette;
  final double brightness;
  final bool isNightMode;
  final bool canGoPrevious;
  final bool canGoNext;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onToggleNightMode;
  final VoidCallback onOpenToc;
  final VoidCallback onOpenSettings;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      padding: EdgeInsets.fromLTRB(
        RevericSpacing.lg,
        RevericSpacing.md,
        RevericSpacing.lg,
        RevericSpacing.sm + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.light_mode_outlined,
                size: 18,
                color: palette.iconColor,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Semantics(
                  label: context.t(LocaleKeys.readingBrightness),
                  slider: true,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      activeTrackColor: palette.iconColor,
                      inactiveTrackColor: palette.divider,
                      thumbColor: palette.iconColor,
                      overlayColor: palette.iconColor.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: brightness,
                      min: _minimumReadingBrightness,
                      max: 1,
                      onChanged: onBrightnessChanged,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              _ReadingControlIconButton(
                icon: isNightMode
                    ? RevericIcons.light_mode_outlined
                    : RevericIcons.nightlight_outlined,
                color: palette.iconColor,
                tooltip: context.t(
                  isNightMode
                      ? LocaleKeys.readingExitNightMode
                      : LocaleKeys.readingNightMode,
                ),
                onPressed: onToggleNightMode,
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Row(
            children: [
              _ReadingControlTile(
                controlKey: const ValueKey('reading-control-previous'),
                icon: RevericIcons.chevron_left,
                label: context.t(LocaleKeys.readingPreviousChapter),
                color: palette.iconColor,
                tooltip: context.t(LocaleKeys.readingPreviousChapter),
                surfaceColor: palette.controlSurface,
                onPressed: canGoPrevious ? onPrevious : null,
              ),
              const SizedBox(width: RevericSpacing.xs),
              _ReadingControlTile(
                controlKey: const ValueKey('reading-control-toc'),
                icon: RevericIcons.format_list_bulleted,
                label: context.t(LocaleKeys.readingTableOfContents),
                color: palette.iconColor,
                tooltip: context.t(LocaleKeys.readingTableOfContents),
                surfaceColor: palette.controlSurface,
                onPressed: onOpenToc,
              ),
              const SizedBox(width: RevericSpacing.xs),
              _ReadingControlTile(
                controlKey: const ValueKey('reading-control-settings'),
                icon: RevericIcons.settings_outlined,
                label: context.t(LocaleKeys.readingSettingsTitle),
                color: palette.iconColor,
                tooltip: context.t(LocaleKeys.readingSettingsTitle),
                surfaceColor: palette.controlSurface,
                onPressed: onOpenSettings,
              ),
              const SizedBox(width: RevericSpacing.xs),
              _ReadingControlTile(
                controlKey: const ValueKey('reading-control-next'),
                icon: RevericIcons.chevron_right,
                label: context.t(LocaleKeys.readingNextChapter),
                color: palette.iconColor,
                tooltip: context.t(LocaleKeys.readingNextChapter),
                surfaceColor: palette.controlSurface,
                onPressed: canGoNext ? onNext : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadingControlTile extends StatelessWidget {
  const _ReadingControlTile({
    required this.controlKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
    required this.surfaceColor,
    required this.onPressed,
  });

  final Key controlKey;
  final String icon;
  final String label;
  final Color color;
  final String tooltip;
  final Color surfaceColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final enabled = onPressed != null;
    final resolvedColor = enabled ? color : color.withValues(alpha: 0.38);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: tooltip,
          child: Material(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(RevericRadius.button),
            child: InkWell(
              key: controlKey,
              onTap: onPressed,
              borderRadius: BorderRadius.circular(RevericRadius.button),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.xxs,
                    vertical: RevericSpacing.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RevericIcon(icon, size: 20, color: resolvedColor),
                      const SizedBox(height: RevericSpacing.xxs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: typo.uiTiny.copyWith(color: resolvedColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 目录 Bottom Sheet
// ---------------------------------------------------------------------------

class _MobileReadingTocSheet extends StatefulWidget {
  const _MobileReadingTocSheet({
    required this.novelTitle,
    required this.chapters,
    required this.currentChapterId,
    required this.palette,
  });

  final String novelTitle;
  final List<Chapter> chapters;
  final String? currentChapterId;
  final ReadingPalette palette;

  @override
  State<_MobileReadingTocSheet> createState() => _MobileReadingTocSheetState();
}

class _MobileReadingTocSheetState extends State<_MobileReadingTocSheet> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _selectedScrollOffset(
        widget.chapters,
        widget.currentChapterId,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    return SafeArea(
      top: false,
      child: Column(
        key: const ValueKey('reading-toc-sheet'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x4l,
              RevericSpacing.x2l,
              RevericSpacing.x4l,
              RevericSpacing.x3l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.readingTableOfContents),
                  style: typo.heading2.copyWith(
                    color: widget.palette.chapterTitle,
                  ),
                ),
                const SizedBox(height: RevericSpacing.xs),
                Text(
                  widget.novelTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.ui.copyWith(color: widget.palette.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: widget.palette.divider),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemExtent: _readingTocItemExtent,
              itemCount: widget.chapters.length,
              itemBuilder: (context, index) {
                final chapter = widget.chapters[index];
                final isSelected = chapter.id == widget.currentChapterId;
                final textColor = isSelected
                    ? widget.palette.chapterTitle
                    : widget.palette.textPrimary;
                return Material(
                  color: isSelected
                      ? widget.palette.controlSurface
                      : widget.palette.background,
                  child: InkWell(
                    key: ValueKey('reading-toc-chapter-${chapter.id}'),
                    onTap: () => Navigator.of(context).pop(chapter.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.x4l,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: widget.palette.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: RevericSpacing.x4l,
                            child: isSelected
                                ? RevericIcon(
                                    RevericIcons.book_open,
                                    size: 16,
                                    color: textColor,
                                  )
                                : null,
                          ),
                          const SizedBox(width: RevericSpacing.sm),
                          Expanded(
                            child: Text(
                              readingChapterTitle(context, chapter),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: (isSelected ? typo.uiSemibold : typo.ui)
                                  .copyWith(color: textColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

double _selectedScrollOffset(List<Chapter> chapters, String? chapterId) {
  final selectedIndex = chapters.indexWhere(
    (chapter) => chapter.id == chapterId,
  );
  return selectedIndex > 2 ? (selectedIndex - 2) * _readingTocItemExtent : 0;
}

// ---------------------------------------------------------------------------
// 空状态
// ---------------------------------------------------------------------------

class _ReadingEmptyState extends StatelessWidget {
  const _ReadingEmptyState({
    required this.palette,
    required this.typo,
    required this.message,
    required this.description,
  });

  final ReadingPalette palette;
  final RevericTypography typo;
  final String message;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.book_open,
              size: 48,
              color: palette.textSecondary,
            ),
            const SizedBox(height: RevericSpacing.x3l),
            Text(
              message,
              style: typo.heading2.copyWith(color: palette.textPrimary),
              textAlign: TextAlign.center,
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.xs),
              Text(
                description,
                style: typo.ui.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通用图标按钮
// ---------------------------------------------------------------------------

class _ReadingControlIconButton extends StatelessWidget {
  const _ReadingControlIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final String icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(
        width:
            RevericSizes.iconButtonSize + RevericSizes.iconButtonPadding * 2,
        height:
            RevericSizes.iconButtonSize + RevericSizes.iconButtonPadding * 2,
      ),
      padding: const EdgeInsets.all(RevericSizes.iconButtonPadding),
      icon: RevericIcon(
        icon,
        size: 18,
        color: onPressed == null ? color.withValues(alpha: 0.38) : color,
      ),
      splashRadius: 20,
    );
  }
}

// ---------------------------------------------------------------------------
// 阅读设置 BottomSheet
// ---------------------------------------------------------------------------

class _MobileReadingSettingsSheet extends ConsumerWidget {
  const _MobileReadingSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x4l,
              RevericSpacing.sm,
              RevericSpacing.x2l,
              RevericSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.readingSettingsTitle),
                    style: typo.heading2.copyWith(color: colors.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: context.t(LocaleKeys.commonClose),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: RevericIcon(
                    RevericIcons.close_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(RevericSpacing.x4l),
              child: ReadingSettingsControls(
                compact: true,
                platform: ReadingSettingsPlatform.mobile,
              ),
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.sm,
                RevericSpacing.x2l,
                RevericSpacing.x5l,
              ),
              child: ReadingSettingsResetButton(
                onPressed: notifier.resetReadingTypography,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 生命周期监听
// ---------------------------------------------------------------------------

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver({required this.onPaused});

  final VoidCallback onPaused;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      onPaused();
    }
  }
}
