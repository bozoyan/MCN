// 职责: 「当前进展」面板 — 展示全书状态快照正文与情绪张力曲线，支持就地 Markdown 编辑快照内容（桌面/移动共用）。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/mobile/pages/novel_editor_page.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/database/novel_content_daos/novel_state_snapshot_dao.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/widget-decomposition.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/horizontal_wheel_scroll.dart';
import '../components/reveric_segmented_control.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../providers/novel_providers.dart';
import '../theme/theme.dart';
import 'ai/markdown_code_block.dart';
import 'md/reveric_markdown_editor.dart';

final _log = AppLogger.forModule('StoryProgress');

/// 至少五个有张力数据的章节才能形成可读趋势。
const int _minimumTensionPointCount = 5;

/// 全书状态快照面板。
///
/// 快照由编年史者在处理章节后写入，是续写时的权威状态来源；这里让用户能看见
/// AI 到底记住了什么、记得对不对。发现记错时可以就地编辑 —— 保存会以
/// 用户身份写入一条新 active 快照，后续编年史者在这条快照上继续更新。
class StoryProgressPanel extends HookConsumerWidget {
  const StoryProgressPanel({
    super.key,
    required this.databasePath,
    required this.chapters,
    this.padding = const EdgeInsets.fromLTRB(
      RevericSpacing.x6l,
      RevericSpacing.x4l,
      RevericSpacing.x6l,
      RevericSpacing.x6l,
    ),
  });

  final String? databasePath;
  final List<Chapter> chapters;

  /// 外层滚动区内边距；移动端传入更紧的边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = useState(false);

    final path = databasePath;
    if (path == null || path.trim().isEmpty) {
      return const _StoryProgressEmptyState();
    }

    final snapshotAsync = ref.watch(currentStateSnapshotProvider(path));
    final snapshot = snapshotAsync.asData?.value;

    // 曲线数据来自章节自身的 tension/emotion，不依赖快照；至少五个有效点
    // 才能形成趋势，单点不展示。
    final tensionPoints = _buildTensionPoints(chapters);

    final hasTensionCurve = tensionPoints.length >= _minimumTensionPointCount;

    if (snapshot == null && !hasTensionCurve) {
      return const _StoryProgressEmptyState();
    }

    final isEditing = editing.value && snapshot != null;

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StoryProgressHeader(
            onEdit: snapshot == null || isEditing
                ? null
                : () => editing.value = true,
          ),
          if (hasTensionCurve) ...[
            const SizedBox(height: RevericSpacing.x3l),
            _TensionCurveCard(points: tensionPoints),
          ],
          if (snapshot != null) ...[
            const SizedBox(height: RevericSpacing.x3l),
            if (isEditing)
              // 换快照要重建编辑态：controller 的初值只在首次挂载时取。
              _SnapshotEditCard(
                key: ValueKey<String>('storyProgressEdit_${snapshot.id}'),
                databasePath: path,
                snapshot: snapshot,
                onClose: () => editing.value = false,
              )
            else
              _SnapshotBodyCard(content: snapshot.content),
          ],
        ],
      ),
    );
  }
}

/// 一个有紧张度数据的章节点。没打分的章节不进曲线。
class _TensionPoint {
  const _TensionPoint({
    required this.chapterNum,
    required this.tension,
    required this.emotion,
  });

  final int chapterNum;
  final int tension;
  final List<String> emotion;
}

List<_TensionPoint> _buildTensionPoints(List<Chapter> chapters) {
  final points = <_TensionPoint>[];
  for (final chapter in chapters) {
    if (!chapter.isChapter) {
      continue;
    }
    final tension = chapter.tension;
    final chapterNum = chapter.chapterNum;
    if (tension == null || chapterNum == null) {
      continue;
    }
    points.add(
      _TensionPoint(
        chapterNum: chapterNum,
        tension: tension,
        emotion: chapter.emotion ?? const <String>[],
      ),
    );
  }
  points.sort((a, b) => a.chapterNum.compareTo(b.chapterNum));
  return points;
}

/// 曲线上的一段：把连续 step 章聚合成一个点，紧张度取段内均值。
///
/// step == 1 时退化为单章，[startChapterNum] == [endChapterNum]。
class _TensionBucket {
  const _TensionBucket({
    required this.startChapterNum,
    required this.endChapterNum,
    required this.tension,
    required this.emotion,
    required this.sampleCount,
  });

  final int startChapterNum;
  final int endChapterNum;

  /// 段内已打分章节的紧张度均值（1-10）。
  final double tension;

  /// 段内出现次数最多的情绪标签；没有情绪时为空串。
  final String emotion;

  /// 参与均值的章节数（未被编年史者处理的章节不计入）。
  final int sampleCount;

  String get label => startChapterNum == endChapterNum
      ? '$startChapterNum'
      : '$startChapterNum-$endChapterNum';
}

/// 采样间隔候选梯度。自动挡与手动挡都从这里取值，保证两者刻度一致。
const List<int> _tensionStepLadder = [1, 2, 5, 10, 20, 50, 100];

/// 手动挡可选间隔；null 表示「自动」。
const List<int?> _tensionStepOptions = [null, 1, 5, 10, 20];

/// 一屏内希望看到的点数上限 —— 再密就看不出节奏了，这正是要采样的原因。
const int _tensionTargetBuckets = 30;

/// 自动间隔：章节跨度越大，间隔越大，让点数收敛到 [_tensionTargetBuckets] 以内。
int autoTensionStep(int chapterSpan) {
  if (chapterSpan <= 0) {
    return 1;
  }
  for (final step in _tensionStepLadder) {
    if ((chapterSpan / step).ceil() <= _tensionTargetBuckets) {
      return step;
    }
  }
  return _tensionStepLadder.last;
}

/// 按章号把点归入固定宽度的区间并求均值。空区间（该段没有任何已打分章节）
/// 直接跳过，不在曲线上留断点。
List<_TensionBucket> _bucketTensionPoints(
  List<_TensionPoint> points,
  int step,
) {
  if (points.isEmpty) {
    return const [];
  }
  final safeStep = step < 1 ? 1 : step;
  if (safeStep == 1) {
    return [
      for (final point in points)
        _TensionBucket(
          startChapterNum: point.chapterNum,
          endChapterNum: point.chapterNum,
          tension: point.tension.toDouble(),
          emotion: point.emotion.isEmpty ? '' : point.emotion.first,
          sampleCount: 1,
        ),
    ];
  }

  final maxChapterNum = points.last.chapterNum;
  final grouped = <int, List<_TensionPoint>>{};
  for (final point in points) {
    final index = (point.chapterNum - 1) ~/ safeStep;
    grouped.putIfAbsent(index, () => <_TensionPoint>[]).add(point);
  }

  final indices = grouped.keys.toList()..sort();
  return [
    for (final index in indices)
      () {
        final group = grouped[index]!;
        final sum = group.fold<int>(0, (total, p) => total + p.tension);
        return _TensionBucket(
          // 刻度用区间边界而非实际章号：用户调的是「每 N 章」，
          // 标签跟着边界走才对得上这个心智模型。末段按实际最大章号收口。
          startChapterNum: index * safeStep + 1,
          endChapterNum: ((index + 1) * safeStep).clamp(1, maxChapterNum),
          tension: sum / group.length,
          emotion: _dominantEmotion(group),
          sampleCount: group.length,
        );
      }(),
  ];
}

/// 段内最高频情绪标签；并列时取先出现的那个。
String _dominantEmotion(List<_TensionPoint> group) {
  final counts = <String, int>{};
  for (final point in group) {
    for (final tag in point.emotion) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) {
    return '';
  }
  var best = '';
  var bestCount = 0;
  for (final entry in counts.entries) {
    if (entry.value > bestCount) {
      best = entry.key;
      bestCount = entry.value;
    }
  }
  return best;
}

class _StoryProgressHeader extends StatelessWidget {
  const _StoryProgressHeader({this.onEdit});

  /// 非空时展示编辑入口；仅在已有快照时可编辑。
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          context.t(LocaleKeys.workspaceStoryProgress),
          style: typo.heading2.copyWith(color: colors.textPrimary),
        ),
        if (onEdit != null) ...[
          const Spacer(),
          IconButton(
            tooltip: context.t(LocaleKeys.workspaceStoryProgressEdit),
            onPressed: onEdit,
            icon: RevericIcon(
              RevericIcons.edit_outlined,
              size: 18,
              color: colors.textMuted,
            ),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

class _SnapshotBodyCard extends StatelessWidget {
  const _SnapshotBodyCard({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: SelectionArea(
        child: GptMarkdown(content, codeBuilder: buildMarkdownCodeBlock),
      ),
    );
  }
}

/// 情绪张力曲线卡片。
///
/// 几百章时逐章画会退化成一条锯齿噪声，所以按「每 N 章取均值」采样；
/// N 默认随章节跨度自适应，用户也可以手动挡到固定值。
class _TensionCurveCard extends HookWidget {
  const _TensionCurveCard({required this.points});

  final List<_TensionPoint> points;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    // null = 自动挡（跟着章节跨度走）；非 null = 用户手动锁定的间隔。
    final stepOverride = useState<int?>(null);

    final chapterSpan = points.isEmpty ? 0 : points.last.chapterNum;
    final effectiveStep = stepOverride.value ?? autoTensionStep(chapterSpan);
    final buckets = _bucketTensionPoints(points, effectiveStep);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.timeline_outlined,
                size: 16,
                color: colors.textMuted,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.workspaceStoryProgressTensionCurve),
                  style: typo.uiSemibold.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (points.length > 1) ...[
                const SizedBox(width: RevericSpacing.md),
                Flexible(
                  child: Text(
                    effectiveStep == 1
                        ? context.t(
                            LocaleKeys
                                .workspaceStoryProgressTensionIntervalPerChapter,
                          )
                        : context.t(
                            LocaleKeys.workspaceStoryProgressTensionAveraged,
                            namedArgs: {'count': '$effectiveStep'},
                          ),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ],
          ),
          // 间隔选择单独一行，避免窄屏与标题挤在同一行溢出。
          if (points.length > 1) ...[
            const SizedBox(height: RevericSpacing.md),
            _TensionIntervalSelector(
              selected: stepOverride.value,
              onChanged: (value) => stepOverride.value = value,
            ),
          ],
          const SizedBox(height: RevericSpacing.x2l),
          if (buckets.isEmpty)
            Text(
              context.t(LocaleKeys.workspaceStoryProgressNoTension),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            )
          else
            _TensionChart(buckets: buckets),
        ],
      ),
    );
  }
}

/// 采样间隔选择器：自动 + 若干固定挡位。
class _TensionIntervalSelector extends StatelessWidget {
  const _TensionIntervalSelector({
    required this.selected,
    required this.onChanged,
  });

  /// null 表示自动挡。
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);

    String labelFor(int? step) {
      if (step == null) {
        return context.t(LocaleKeys.workspaceStoryProgressTensionIntervalAuto);
      }
      if (step == 1) {
        return context.t(
          LocaleKeys.workspaceStoryProgressTensionIntervalPerChapter,
        );
      }
      return context.t(
        LocaleKeys.workspaceStoryProgressTensionIntervalChapters,
        namedArgs: {'count': '$step'},
      );
    }

    final segments = [
      for (final option in _tensionStepOptions)
        RevericSegment<int>(value: option ?? 0, label: labelFor(option)),
    ];
    // 等宽分段按最长本地化标签预留宽度，窄屏横向滚动而不压缩文案。
    var segmentWidth = RevericSizes.touchTargetSize;
    for (final segment in segments) {
      final painter = TextPainter(
        text: TextSpan(text: segment.label, style: typo.uiSemibold),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width + RevericSpacing.x2l;
      if (width > segmentWidth) {
        segmentWidth = width;
      }
      painter.dispose();
    }

    return HorizontalWheelScroll(
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width:
              segmentWidth * segments.length +
              2 * RevericSizes.segmentTrackPadding,
          child: RevericSegmentedControl<int>(
            segments: segments,
            selected: selected ?? 0,
            onChanged: (value) => onChanged(value == 0 ? null : value),
          ),
        ),
      ),
    );
  }
}

/// 折线图：X 轴章节区间，Y 轴紧张度 1-10，节点下方挂情绪 chip。
///
/// 采样后仍可能超出一屏，此时横向滚动而不再压缩 —— 挤成一团的曲线看不出节奏，
/// 而看节奏正是这个面板存在的唯一理由。
class _TensionChart extends StatelessWidget {
  const _TensionChart({required this.buckets});

  final List<_TensionBucket> buckets;

  /// 单点最小槽宽；点少时按可用宽度拉开，点多时保持这个下限并横向滚动。
  static const double _minSlotWidth = 56;
  static const double _chartHeight = 160;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 采样后点数通常远少于可用槽位，铺满卡片宽度而不是缩在左半边。
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _minSlotWidth * buckets.length;
        final slotWidth = (available / buckets.length).clamp(
          _minSlotWidth,
          double.infinity,
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: slotWidth * buckets.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: _chartHeight,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TensionChartPainter(
                      buckets: buckets,
                      lineColor: colors.accent,
                      gridColor: colors.borderSubtle,
                      dotFill: colors.surface,
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.sm),
                Row(
                  children: [
                    for (final bucket in buckets)
                      SizedBox(
                        width: slotWidth,
                        child: Column(
                          children: [
                            Text(
                              bucket.label,
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (bucket.emotion.isNotEmpty) ...[
                              const SizedBox(height: RevericSpacing.xxs),
                              Text(
                                bucket.emotion,
                                style: typo.uiTiny.copyWith(
                                  color: colors.textSubtle,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TensionChartPainter extends CustomPainter {
  const _TensionChartPainter({
    required this.buckets,
    required this.lineColor,
    required this.gridColor,
    required this.dotFill,
  });

  final List<_TensionBucket> buckets;
  final Color lineColor;
  final Color gridColor;
  final Color dotFill;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) {
      return;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    // Y 轴固定 1-10 满量程：跟着数据自适应的话，每本书的曲线尺度都不一样，
    // 就没法横向比较「这章到底算不算高潮」。
    for (var level = 0; level <= 10; level += 2) {
      final y = size.height - (level / 10) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slotWidth = size.width / buckets.length;
    final offsets = <Offset>[
      for (var index = 0; index < buckets.length; index++)
        Offset(
          slotWidth * index + slotWidth / 2,
          size.height -
              (buckets[index].tension.clamp(0, 10) / 10) * size.height,
        ),
    ];

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final dotStroke = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotCore = Paint()..color = dotFill;
    for (final offset in offsets) {
      canvas.drawCircle(offset, 3.5, dotCore);
      canvas.drawCircle(offset, 3.5, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TensionChartPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.dotFill != dotFill ||
        oldDelegate.buckets.length != buckets.length ||
        !_sameTensions(oldDelegate.buckets, buckets);
  }

  static bool _sameTensions(List<_TensionBucket> a, List<_TensionBucket> b) {
    for (var index = 0; index < a.length; index++) {
      if (a[index].tension != b[index].tension ||
          a[index].startChapterNum != b[index].startChapterNum ||
          a[index].endChapterNum != b[index].endChapterNum) {
        return false;
      }
    }
    return true;
  }
}

class _StoryProgressEmptyState extends StatelessWidget {
  const _StoryProgressEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerHigh,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Center(
                child: RevericIcon(
                  RevericIcons.timeline_outlined,
                  color: colors.textMuted,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.workspaceStoryProgressEmpty),
              style: typo.heading2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                context.t(LocaleKeys.workspaceStoryProgressEmptyHint),
                style: typo.ui.copyWith(color: colors.textMuted, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 快照正文的就地编辑区，替换 [_SnapshotBodyCard] 出现在面板同一位置。
///
/// 保存时以用户身份写入一条新 active 快照，
/// 旧的快照转为 superseded；编年史者后续会基于新快照继续更新。
class _SnapshotEditCard extends HookConsumerWidget {
  const _SnapshotEditCard({
    super.key,
    required this.databasePath,
    required this.snapshot,
    required this.onClose,
  });

  final String databasePath;
  final NovelStateSnapshot snapshot;

  /// 保存成功或取消后退出编辑态。
  final VoidCallback onClose;

  /// 空快照也要有可点的输入区，不要塌成一行。
  static const double _minEditorHeight = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final controller = useTextEditingController(text: snapshot.content);
    final focusNode = useFocusNode();
    final isSaving = useState(false);

    useEffect(() {
      // 进入编辑态直接落焦，省掉一次点击；光标停在正文开头，
      // 否则默认落在末尾会把整个面板滚到快照底部。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        controller.selection = const TextSelection.collapsed(offset: 0);
        focusNode.requestFocus();
      });
      return null;
    }, const <Object?>[]);

    Future<void> handleSave() async {
      if (isSaving.value || controller.text.trim().isEmpty) {
        return;
      }
      isSaving.value = true;
      try {
        await ref
            .read(novelContentServiceProvider(databasePath))
            .writeCurrentStateSnapshot(
              content: controller.text,
              createdBy: novelStateSnapshotCreatedByUser,
            );
        onClose();
      } catch (error, stackTrace) {
        _log.error(
          '[DB] table=novel_state_snapshots op=USER_EDIT_SNAPSHOT '
          'id=${snapshot.id}',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      } finally {
        if (context.mounted) {
          isSaving.value = false;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevericMarkdownEditor(
          controller: controller,
          focusNode: focusNode,
          autoHeight: true,
          minHeight: _minEditorHeight,
          disabled: isSaving.value,
        ),
        const SizedBox(height: RevericSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                context.t(LocaleKeys.workspaceStoryProgressEditHint),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
            const SizedBox(width: RevericSpacing.x2l),
            TextButton(
              onPressed: isSaving.value ? null : onClose,
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x2l,
                  vertical: RevericSpacing.sm,
                ),
              ),
              child: Text(context.t(LocaleKeys.commonCancel)),
            ),
            const SizedBox(width: RevericSpacing.xs),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasContent = value.text.trim().isNotEmpty;
                return FilledButton(
                  onPressed: isSaving.value || !hasContent ? null : handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.canvas,
                    disabledBackgroundColor: colors.accent.withValues(
                      alpha: 0.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(RevericRadius.button),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.x4l,
                      vertical: RevericSpacing.sm,
                    ),
                    minimumSize: const Size(0, RevericSizes.buttonHeightSm),
                  ),
                  child: isSaving.value
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(colors.canvas),
                          ),
                        )
                      : Text(context.t(LocaleKeys.commonSave)),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
