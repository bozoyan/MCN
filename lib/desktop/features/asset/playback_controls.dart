// 职责: 将播放进度流限制在媒体预览控制区，提供播放暂停与拖动定位。
// 关联文件:
//   lib/desktop/features/asset/media_preview.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/assets.json
//   assets/translations/zh-CN/assets.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class PlaybackControls extends HookWidget {
  const PlaybackControls({super.key, required this.player});
  final VideoPlayerController player;
  @override
  Widget build(BuildContext context) {
    final value = useValueListenable(player);
    final playing = value.isPlaying;
    final position = value.position;
    final duration = value.duration;
    final completed = value.isCompleted;
    if (value.hasError) {
      return Text(context.t(LocaleKeys.mediaPreviewFailed));
    }
    final maximum = duration.inMilliseconds.toDouble();
    // Show the full duration at EOF even if the last frame starts earlier.
    final displayedPosition = completed ? duration : position;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        RevericIconButton(
          icon: playing ? RevericIcons.pause : RevericIcons.play_arrow,
          tooltip: context.t(
            playing ? LocaleKeys.commonPause : LocaleKeys.commonPlay,
          ),
          onPressed: () => playing ? player.pause() : player.play(),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: RevericSpacing.xxs,
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.border,
              thumbColor: colors.accent,
              overlayColor: colors.hover,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: RevericSpacing.xs,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: RevericSpacing.lg,
              ),
            ),
            child: Slider(
              value: displayedPosition.inMilliseconds.toDouble().clamp(
                0,
                maximum,
              ),
              max: maximum > 0 ? maximum : 1,
              onChanged: maximum > 0
                  ? (value) =>
                        player.seekTo(Duration(milliseconds: value.round()))
                  : null,
            ),
          ),
        ),
        Text(
          '${_clock(displayedPosition)} / ${_clock(duration)}',
          style: typo.uiSmall.copyWith(
            color: colors.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _clock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
