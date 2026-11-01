// 职责: 在制作画布的节点卡片里就地播放视频 / 音频，提供播放暂停与拖动定位，并向工具条提供当前播放位置。
// 关联文件:
//   lib/desktop/features/production/node_card.dart
//   lib/desktop/features/production/node_bar.dart
//   lib/shared/services/production/playback_service.dart
//   lib/shared/providers/production_media.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/production_media.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/playback_service.dart';
import '../../../shared/theme/theme.dart';
import 'node_card.dart' show ProductionAssetThumb, ProductionPlayMark;
import 'support.dart';

/// 节点卡片在全局播放器里的拥有者标识。
String productionInlineOwner(String nodeId) => 'production-node/$nodeId';

/// 节点卡片正在播放时的播放位置；没在卡片里播放时为 null。
Duration? productionInlinePosition(PlaybackService playback, String nodeId) =>
    playback.active.value == productionInlineOwner(nodeId)
    ? playback.player.value.position
    : null;

/// 卡片就地播放的会话：[start] 打开并播放；别处（预览弹窗、剪辑）打开播放器后 active 自动变回 false。
/// 取消选中、卸载或换了文件（重新采用）时归还播放器。[nodeId] 为 null 时不可播放，始终不 active。
({bool active, bool opening, VoidCallback start}) useProductionInlinePlayback(
  BuildContext context,
  PlaybackService playback, {
  required ProductionCanvasService service,
  required String? nodeId,
  required String filePath,
  required bool selected,
}) {
  final owner = nodeId == null ? null : productionInlineOwner(nodeId);
  final current = useValueListenable(playback.active);
  final opening = useState(false);
  void release() {
    if (owner != null) {
      unawaited(playback.release(owner));
    }
  }

  useEffect(() {
    if (!selected) {
      release();
    }
    return null;
  }, [selected, playback, owner]);
  useEffect(() => release, [playback, owner]);
  useValueChanged<String, void>(filePath, (_, _) => release());

  void start() => productionRun(context, () async {
    if (owner == null || opening.value) {
      return;
    }
    opening.value = true;
    try {
      await playback.open(
        owner: owner,
        path: service.library.resolvePath(filePath),
        play: true,
      );
    } finally {
      if (context.mounted) {
        opening.value = false;
      }
    }
  });

  return (
    active: owner != null && current == owner,
    opening: opening.value,
    start: start,
  );
}

/// 常态是缩略占位加播放标记；悬停片刻预览，移开结束；点击播放不受移开影响。
class ProductionInlineVideo extends HookConsumerWidget {
  const ProductionInlineVideo({
    super.key,
    required this.service,
    required this.nodeId,
    required this.filePath,
    required this.selected,
  });
  final ProductionCanvasService service;
  final String nodeId;
  final String filePath;
  final bool selected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackServiceProvider);
    final (:active, :opening, :start) = useProductionInlinePlayback(
      context,
      playback,
      service: service,
      nodeId: nodeId,
      filePath: filePath,
      selected: selected,
    );
    final hoverTimer = useRef<Timer?>(null);
    final hoverPlayback = useRef(false);
    void cancelHover() {
      hoverTimer.value?.cancel();
      hoverTimer.value = null;
      if (hoverPlayback.value) {
        hoverPlayback.value = false;
        unawaited(playback.release(productionInlineOwner(nodeId)));
      }
    }

    useEffect(() => cancelHover, [playback, nodeId, filePath, service]);

    void playOnClick() {
      hoverTimer.value?.cancel();
      hoverPlayback.value = false;
      start();
    }

    final player = active ? playback.player : null;
    return MouseRegion(
      onEnter: (event) {
        if (event.kind != PointerDeviceKind.mouse || active || opening) {
          return;
        }
        hoverTimer.value?.cancel();
        hoverTimer.value = Timer(const Duration(milliseconds: 500), () {
          hoverPlayback.value = true;
          start();
        });
      },
      onExit: (_) => cancelHover(),
      child: player == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                ProductionAssetThumb(service: service, filePath: filePath),
                Center(
                  child: opening
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ProductionPlayMark(onTap: playOnClick),
                ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: RevericTheme.colorsOf(context).surfaceDim,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: player.value.aspectRatio,
                      child: GestureDetector(
                        onTap: playback.playOrPause,
                        child: VideoPlayer(player),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ProductionInlineControls(player: player),
                ),
              ],
            ),
    );
  }
}

/// 卡片里的播放暂停、进度条和时间；只有这一条随播放进度重建。
class ProductionInlineControls extends HookWidget {
  const ProductionInlineControls({
    super.key,
    required this.player,
    this.overlay = true,
  });
  final VideoPlayerController player;

  /// 叠在画面底部：浅色前景加渐变衬底；false 时直接排在卡片底色上（音频卡片）。
  final bool overlay;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final value = useValueListenable(player);
    final duration = value.duration;
    final position = value.isCompleted ? duration : value.position;
    final total = duration.inMilliseconds;
    final progress = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final foreground = overlay ? colors.onAccent : colors.textSecondary;
    void seek(double dx, double width) {
      if (total > 0 && width > 0) {
        player.seekTo(
          Duration(
            milliseconds: ((dx / width).clamp(0.0, 1.0) * total).round(),
          ),
        );
      }
    }

    final row = Row(
      children: [
        Tooltip(
          message: context.t(
            value.isPlaying ? LocaleKeys.commonPause : LocaleKeys.commonPlay,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => value.isPlaying ? player.pause() : player.play(),
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.xxs),
              child: RevericIcon(
                value.isPlaying
                    ? RevericIcons.pause
                    : RevericIcons.play_arrow,
                size: 14,
                color: foreground,
              ),
            ),
          ),
        ),
        const SizedBox(width: RevericSpacing.xs),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  seek(details.localPosition.dx, box.maxWidth),
              onHorizontalDragUpdate: (details) =>
                  seek(details.localPosition.dx, box.maxWidth),
              child: SizedBox(
                height: 16,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: foreground,
                      backgroundColor: foreground.withValues(alpha: .3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Text(
          '${productionClock(position)} / ${productionClock(duration)}',
          style: typo.uiTiny.copyWith(
            color: foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    if (!overlay) {
      return row;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.xs,
        RevericSpacing.lg,
        RevericSpacing.sm,
        RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.textPrimary.withValues(alpha: 0),
            colors.textPrimary.withValues(alpha: .5),
          ],
        ),
      ),
      child: row,
    );
  }
}

/// 「分:秒」；不足一分钟的视频也写成 0:05。
String productionClock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
