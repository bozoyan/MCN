// 职责: 视频节点「裁剪时长」弹窗：边看画面边拖入点和出点，确认后返回要保留的区间。
// 关联文件:
//   lib/desktop/features/production/node_bar.dart
//   lib/desktop/features/production/inline_media.dart
//   lib/shared/providers/production_media.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/providers/production_media.dart';
import '../../../shared/theme/theme.dart';

final _log = AppLogger.forModule('ProductionTrim');

/// 保留区间至少这么长。
const _minLength = Duration(milliseconds: 100);

/// 返回要保留的 [start, end)；取消为 null。[path] 是资产库内的存储路径。
Future<({Duration start, Duration end})?> showProductionTrimDialog(
  BuildContext context, {
  required String path,
}) => showRevericDialog(
  context: context,
  builder: (_) => _TrimDialog(path: path),
);

class _TrimDialog extends HookConsumerWidget {
  const _TrimDialog({required this.path});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final library = ref.watch(mediaLibraryServiceProvider);
    final playback = ref.watch(playbackServiceProvider);
    const owner = 'production-trim';
    final ready = useValueListenable(playback.active) == owner;
    final failed = useState(false);
    final range = useState<RangeValues?>(null);
    useEffect(() {
      var alive = true;
      Future<void>(() async {
        try {
          await playback.open(owner: owner, path: library.resolvePath(path));
        } catch (error, stack) {
          _log.error('open failed', error: error, stackTrace: stack);
          if (alive) {
            failed.value = true;
          }
        }
      });
      return () {
        alive = false;
        unawaited(playback.release(owner));
      };
    }, [playback, library, path]);

    final player = ready ? playback.player : null;
    final total = player?.value.duration ?? Duration.zero;
    final values =
        range.value ?? RangeValues(0, total.inMilliseconds.toDouble());
    final start = Duration(milliseconds: values.start.round());
    final end = Duration(milliseconds: values.end.round());
    final changed = start > Duration.zero || end < total;

    return RevericDialog(
      title: context.t(LocaleKeys.productionTrim),
      width: RevericSizes.productionTrimDialogWidth,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            child: ColoredBox(
              color: colors.surfaceDim,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: failed.value
                    ? Center(
                        child: Text(
                          context.t(LocaleKeys.mediaPreviewFailed),
                          style: typo.uiSmall.copyWith(color: colors.error),
                        ),
                      )
                    : player == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: AspectRatio(
                          aspectRatio: player.value.aspectRatio,
                          child: GestureDetector(
                            onTap: playback.playOrPause,
                            child: VideoPlayer(player),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          RangeSlider(
            values: values,
            max: total > Duration.zero ? total.inMilliseconds.toDouble() : 1,
            activeColor: colors.accent,
            inactiveColor: colors.border,
            onChanged: player == null || total <= _minLength
                ? null
                : (next) {
                    if (next.end - next.start < _minLength.inMilliseconds) {
                      return;
                    }
                    // 拖哪一端就把画面定到哪一端，方便对准切点。
                    final moved = next.start != values.start
                        ? next.start
                        : next.end;
                    range.value = next;
                    unawaited(player.pause());
                    unawaited(
                      player.seekTo(Duration(milliseconds: moved.round())),
                    );
                  },
          ),
          Text(
            context.t(
              LocaleKeys.productionTrimRange,
              namedArgs: {
                'start': _clock(start),
                'end': _clock(end),
                'duration': _clock(end - start),
              },
            ),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonConfirm),
          onPressed: changed
              ? () => Navigator.of(context).pop((start: start, end: end))
              : null,
        ),
      ],
    );
  }
}

/// 「分:秒.十分位」，切点要精确到零点一秒。
String _clock(Duration value) {
  final tenths = (value.inMilliseconds % 1000) ~/ 100;
  return '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}.$tenths';
}
