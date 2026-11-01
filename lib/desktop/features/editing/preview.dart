// 职责: 预览区与走带条：为冻结工程准备连续预览并播放，修改后停在旧预览的最后一帧，暂停时显示播放头处的源素材画面。
// 关联文件:
//   lib/desktop/features/editing/controller.dart
//   lib/shared/services/editing/render_service.dart
//   lib/shared/services/production/playback_service.dart
//   lib/shared/services/production/frame_capture.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/production_media.dart';
import '../../../shared/services/editing/render_service.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/services/production/ffmpeg_runner.dart';
import '../../../shared/services/production/frame_capture.dart';
import '../../../shared/services/production/media_service.dart';
import '../../../shared/models/editing/document.dart';
import '../../../shared/models/production/media.dart';
import '../../../shared/theme/theme.dart';
import 'controller.dart';
import 'support.dart';

final _log = AppLogger.forModule('EditingPreview');

class EditingPreview extends HookConsumerWidget {
  const EditingPreview({
    super.key,
    required this.controller,
    required this.renderer,
  });
  final EditingController controller;
  final EditingRenderService renderer;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playbackServiceProvider);
    final session = controller.session;
    final playhead = controller.playhead;
    final document = session.document!;
    final token = useRef<MediaCancellation?>(null);
    final output = useRef<EncodedMedia?>(null);
    final ready = useState(false);
    // 工程改动后停在旧预览的最后一帧，直到重新生成或时间线清空。
    final frozen = useState(false);
    final active = useValueListenable(player.active);
    final busy = useState(false);
    final progress = useState(0.0);
    final generation = useRef(0);
    final syncingPosition = useRef(false);
    final owner = useMemoized(() => Object().hashCode.toString());
    final still = _useStill(controller, renderer.runner, enabled: !ready.value);
    useEffect(() {
      generation.value++;
      busy.value = false;
      final keep =
          (ready.value || frozen.value) &&
          document.totalFrames > 0 &&
          player.active.value == owner;
      ready.value = false;
      frozen.value = keep;
      if (keep) {
        unawaited(player.player.pause());
        unawaited(token.value?.cancel());
        return null;
      }
      final old = output.value;
      output.value = null;
      unawaited(() async {
        await token.value?.cancel();
        await player.release(owner);
        await old?.dispose();
      }());
      return null;
    }, [document]);
    useEffect(() {
      if (!ready.value) {
        return null;
      }
      final activePlayer = player.player;
      void updatePosition() {
        final position = activePlayer.value.position;
        if (ready.value) {
          syncingPosition.value = true;
          playhead.value = editingFrames(
            position.inMicroseconds,
          ).clamp(0, session.document!.totalFrames);
          syncingPosition.value = false;
        }
      }

      activePlayer.addListener(updatePosition);
      return () => activePlayer.removeListener(updatePosition);
    }, [player, owner, ready.value]);
    useEffect(
      () => () {
        generation.value++;
        final pendingToken = token.value;
        final old = output.value;
        output.value = null;
        unawaited(() async {
          await pendingToken?.cancel();
          await player.release(owner);
          await old?.dispose();
        }());
      },
      [player, owner],
    );
    useOnListenableChange(playhead, () {
      if (!ready.value && frozen.value) {
        // 旧预览的画面跟不上新的播放头，改看源素材的帧。
        frozen.value = false;
      }
      if (ready.value && !syncingPosition.value) {
        unawaited(
          editingRun(
            context,
            () => player.player.seekTo(
              Duration(microseconds: editingMicroseconds(playhead.value)),
            ),
          ),
        );
      }
    });
    Future<void> prepare() async {
      final run = ++generation.value;
      final cancellation = MediaCancellation();
      token.value = cancellation;
      busy.value = true;
      try {
        final result = await renderer.render(
          document,
          cancellation: cancellation,
          preview: true,
          progress: (stage, value) {
            if (context.mounted && generation.value == run) {
              progress.value = value;
            }
          },
        );
        if (!context.mounted || generation.value != run) {
          await result.dispose();
          return;
        }
        await player.release(owner);
        await output.value?.dispose();
        output.value = result;
        await player.open(owner: owner, path: result.file.path);
        if (!context.mounted || generation.value != run) {
          await player.release(owner);
          return;
        }
        await player.player.seekTo(
          Duration(microseconds: editingMicroseconds(playhead.value)),
        );
        ready.value = true;
        frozen.value = false;
        await player.player.play();
      } on MediaException catch (error) {
        if (error.reason != MediaFailure.cancelled) {
          rethrow;
        }
        // Export cancels the active preview encode. Resume only the same
        // outstanding preview request once the export has released the renderer.
        await renderer.whenIdle;
        if (context.mounted && generation.value == run) {
          await prepare();
        }
      } finally {
        if (context.mounted && generation.value == run) {
          busy.value = false;
        }
      }
    }

    Future<void> toggle() async {
      if (ready.value) {
        await player.playOrPause();
      } else if (!busy.value && document.totalFrames > 0) {
        if (playhead.value >= document.totalFrames) {
          playhead.value = 0;
        }
        await prepare();
      }
    }

    final latest = useRef(toggle)..value = toggle;
    useEffect(() {
      controller.togglePlay = () => editingRun(context, latest.value);
      return () => controller.togglePlay = null;
    }, [controller]);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final ratio = document.ratio.split(':').map(double.parse).toList();
    final showing = (ready.value || frozen.value) && active == owner;
    final empty = document.totalFrames == 0;
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: colors.surfaceDim,
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Center(
                child: AspectRatio(
                  aspectRatio: ratio[0] / ratio[1],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: ColoredBox(
                      color: colors.surfaceContainerHigh,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (showing)
                            VideoPlayer(player.player)
                          else if (still != null)
                            Image.memory(
                              still,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          if (!ready.value &&
                              !empty &&
                              (busy.value || showing || still == null))
                            ColoredBox(
                              color: showing || still != null
                                  ? colors.surfaceDim.withValues(alpha: .72)
                                  : Colors.transparent,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    RevericSpacing.lg,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        context.t(
                                          busy.value
                                              ? LocaleKeys.editingPreparing
                                              : LocaleKeys.editingPreviewStale,
                                          namedArgs: {
                                            'percent':
                                                '${(progress.value * 100).floor()}',
                                          },
                                        ),
                                        textAlign: TextAlign.center,
                                        style: typo.uiSmall.copyWith(
                                          color: showing || still != null
                                              ? colors.textPrimary
                                              : colors.textMuted,
                                        ),
                                      ),
                                      if (busy.value) ...[
                                        const SizedBox(
                                          height: RevericSpacing.sm,
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: LinearProgressIndicator(
                                            value: progress.value,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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
        ),
        _Transport(
          controller: controller,
          player: ready.value ? player.player : null,
          onToggle: () => editingRun(context, toggle),
        ),
      ],
    );
  }
}

/// 暂停时按播放头从主轨源素材抽一帧；不含叠加层和字幕，只保证拖动播放头时有画面可看。
Uint8List? _useStill(
  EditingController controller,
  FfmpegRunner runner, {
  required bool enabled,
}) {
  final still = useState<Uint8List?>(null);
  final frames = useMemoized(() => <String, Uint8List>{});
  final folder = useMemoized(
    () => Directory.systemTemp.createTemp('reveric_editing_still_'),
  );
  final pending = useRef<MediaCancellation?>(null);
  final timer = useRef<Timer?>(null);
  final serial = useRef(0);
  final live = useRef(true);
  final on = useRef(enabled)..value = enabled;
  final document = controller.session.document;

  Future<void> load() async {
    final doc = controller.session.document;
    if (!live.value || !on.value || doc == null) {
      return;
    }
    // 只采用最后一次请求的结果。
    final ticket = ++serial.value;
    final previous = pending.value;
    pending.value = null;
    await previous?.cancel();
    if (ticket != serial.value) {
      return;
    }
    final frame = controller.playhead.value;
    final clip = doc.mainClips
        .where((c) => frame >= c.startFrame && frame < c.endFrame)
        .firstOrNull;
    final media = clip?.media;
    final path = clip == null || media == null || doc.mainTrack.hidden
        ? null
        : controller.sourceFile(media.source);
    if (clip == null || media == null || path == null) {
      still.value = null;
      return;
    }
    final image = media.source.mediaType == 'image';
    final at = image ? 0 : media.sourceUsAt(frame - clip.startFrame);
    final key = '$path@$at';
    final hit = frames.remove(key);
    if (hit != null) {
      frames[key] = hit;
      still.value = hit;
      return;
    }
    final token = MediaCancellation();
    pending.value = token;
    final output = File('${(await folder).path}/$ticket.png');
    try {
      final bytes = image
          ? await File(path).readAsBytes()
          : await captureMediaFrame(
              runner,
              path,
              output,
              token,
              timestampUs: at,
            );
      if (!live.value || ticket != serial.value) {
        return;
      }
      frames[key] = bytes;
      if (frames.length > 32) {
        frames.remove(frames.keys.first);
      }
      still.value = bytes;
    } on MediaException catch (error) {
      if (error.reason != MediaFailure.cancelled) {
        _log.warning('still frame failed: $error');
      }
    } on FormatException catch (error) {
      // 源素材在该位置没有画面（例如超出实际时长）。
      _log.warning('still frame missing: $error');
      if (live.value && ticket == serial.value) {
        still.value = null;
      }
    } finally {
      if (await output.exists()) {
        await output.delete();
      }
    }
  }

  void request() {
    timer.value?.cancel();
    timer.value = Timer(const Duration(milliseconds: 80), () {
      unawaited(load());
    });
  }

  useOnListenableChange(controller.playhead, () {
    if (on.value) {
      request();
    }
  });
  useEffect(() {
    if (enabled) {
      request();
    }
    return null;
  }, [enabled, document]);
  useEffect(
    () => () {
      live.value = false;
      timer.value?.cancel();
      unawaited(() async {
        await pending.value?.cancel();
        await (await folder).delete(recursive: true);
      }());
    },
    const [],
  );
  return still.value;
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.controller,
    required this.player,
    required this.onToggle,
  });
  final EditingController controller;
  final VideoPlayerController? player;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final doc = controller.doc;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: controller.playhead,
        builder: (context, frame, _) {
          final current = doc.mainClips
              .where((c) => frame >= c.startFrame && frame < c.endFrame)
              .firstOrNull;
          return Row(
            children: [
              Expanded(
                child: Text(
                  doc.totalFrames == 0
                      ? ''
                      : current == null
                      ? context.t(LocaleKeys.editingEnd)
                      : editingClipLabel(controller, current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ),
              RevericIconButton(
                icon: RevericIcons.skip_back,
                tooltip: context.t(LocaleKeys.editingPreviousCut),
                onPressed: controller.previousCut,
              ),
              const SizedBox(width: RevericSpacing.xs),
              ListenableBuilder(
                listenable: player ?? controller.playhead,
                builder: (context, _) {
                  final on = player?.value.isPlaying ?? false;
                  return Tooltip(
                    message: context.t(
                      on ? LocaleKeys.commonPause : LocaleKeys.commonPlay,
                    ),
                    child: Material(
                      color: doc.totalFrames == 0
                          ? colors.accent.withValues(alpha: .4)
                          : colors.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: doc.totalFrames == 0 ? null : onToggle,
                        child: SizedBox.square(
                          dimension: 34,
                          child: Center(
                            child: RevericIcon(
                              on ? RevericIcons.pause : RevericIcons.play_arrow,
                              size: 16,
                              color: colors.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: RevericSpacing.xs),
              RevericIconButton(
                icon: RevericIcons.skip_forward,
                tooltip: context.t(LocaleKeys.editingNextCut),
                onPressed: controller.nextCut,
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: editingTimecode(frame),
                        style: typo.mono.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: ' / ${editingTimecode(doc.totalFrames)}'),
                    ],
                  ),
                  textAlign: TextAlign.right,
                  style: typo.mono.copyWith(color: colors.textSubtle),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
