// 职责: 保存制片画布视图与聊天浮窗展开状态，供画布、剪辑和导演台共用。
// 关联文件:
//   lib/desktop/features/production/region.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/ai/chat/floating.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'production_chat.g.dart';

/// [canvas]：制片页当前停在画布视图；[open]：聊天浮窗展开（否则只剩悬浮球）。
typedef ProductionChatState = ({bool canvas, bool open});

/// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。
@riverpod
class ProductionChat extends _$ProductionChat {
  @override
  ProductionChatState build(String novelId) => (canvas: false, open: false);

  /// 每次进出画布都从悬浮球开始，右栏的展开状态不受影响。
  void setCanvas(bool canvas) {
    // 制片页卸载时延后写入，编辑页可能已经先释放了这个 provider。
    if (!ref.mounted || state.canvas == canvas) {
      return;
    }
    state = (canvas: canvas, open: false);
  }

  void setOpen(bool open) {
    if (state.open == open) {
      return;
    }
    state = (canvas: state.canvas, open: open);
  }
}
