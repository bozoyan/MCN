// 职责: 在音色列表内就地试听，同一时间只播放一条，切换、播完或卸载时释放解码器。
// 关联文件:
//   lib/desktop/features/production/voices.dart
//   lib/desktop/features/production/builtin_voices.dart
//   lib/shared/services/production/runtime.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'dart:async';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/services/production/runtime.dart';

typedef VoicePreview = ({
  String? playing,
  Future<void> Function(String id, Future<VideoPlayerController> Function())
  toggle,
});

/// 再次点击正在播放的条目即停止；点击其他条目先停掉当前再播放。
VoicePreview useVoicePreview() {
  final context = useContext();
  final playing = useState<String?>(null);
  final player = useRef<VideoPlayerController?>(null);
  useEffect(
    () => () {
      final current = player.value;
      player.value = null;
      unawaited(current?.dispose());
    },
    const [],
  );

  Future<void> toggle(
    String id,
    Future<VideoPlayerController> Function() create,
  ) async {
    final same = playing.value == id;
    final previous = player.value;
    player.value = null;
    playing.value = same ? null : id;
    await previous?.dispose();
    if (same) {
      return;
    }
    VideoPlayerController? next;
    try {
      await initializeMediaRuntime();
      next = await create();
      if (!context.mounted || playing.value != id) {
        await next.dispose();
        return;
      }
      player.value = next;
      await next.initialize();
      if (!identical(player.value, next)) {
        return;
      }
      final started = next;
      started.addListener(() {
        if (started.value.isCompleted &&
            identical(player.value, started) &&
            context.mounted) {
          player.value = null;
          playing.value = null;
          unawaited(started.dispose());
        }
      });
      await next.play();
    } catch (_) {
      if (next != null && identical(player.value, next)) {
        player.value = null;
        await next.dispose();
      }
      if (context.mounted && playing.value == id) {
        playing.value = null;
      }
      rethrow;
    }
  }

  return (playing: playing.value, toggle: toggle);
}
