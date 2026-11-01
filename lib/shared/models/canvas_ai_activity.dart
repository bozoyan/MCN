// 职责: 画布 AI 活动事件 — 描述 AI 刚在画布上做了什么、触碰了哪些节点,供 UI 跟随镜头与状态提示
// 关联文件:
//   lib/shared/services/ai/tools_canvas.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart

import 'package:flutter/foundation.dart';

/// AI 在画布上执行的操作类型。
///
/// UI 靠它决定状态条文案与镜头行为(读取类不动镜头);[create_canvas] 与
/// [open_canvas] 还额外驱动宿主打开该画布的详情页。
enum CanvasAiActivityKind {
  /// AI 新建了一张画布。画布页此刻还没打开 —— 宿主(桌面工作区)据此把详情页推上来。
  create_canvas,

  /// AI 要求打开一张已存在的画布(`Write /canvas/{name}/open`)。同样由宿主推页面。
  open_canvas,
  scan,
  add_node,
  update_node,
  remove_node,
  add_edge,
  remove_edge,
  auto_layout,
}

/// 一次画布 AI 操作的快照。
///
/// 由 canvas 工具 handler 在写库成功后上报,经 `CanvasAiActivityNotifier` 广播给
/// 画布 UI。[focusNodeIds] 是本次操作触碰的节点(连线取两端),UI 用它算镜头焦点;
/// 删除与整理布局没有稳定焦点,留空即可 —— 空焦点会被镜头策略当作「看全图」。
@immutable
class CanvasAiActivity {
  const CanvasAiActivity({
    required this.canvasId,
    required this.kind,
    this.focusNodeIds = const <String>[],
    this.seq = 0,
  });

  final String canvasId;
  final CanvasAiActivityKind kind;
  final List<String> focusNodeIds;

  /// 单调递增序号。同一张画布连续两次相同操作在字段上完全相同,
  /// UI 需要 seq 才能区分「新事件」与「重复通知」。
  final int seq;

  /// 是否是纯读取(只驱动状态条文案,不触发镜头动作)。
  bool get isReadOnly => kind == CanvasAiActivityKind.scan;

  CanvasAiActivity copyWithSeq(int seq) {
    return CanvasAiActivity(
      canvasId: canvasId,
      kind: kind,
      focusNodeIds: focusNodeIds,
      seq: seq,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CanvasAiActivity &&
        other.canvasId == canvasId &&
        other.kind == kind &&
        other.seq == seq &&
        listEquals(other.focusNodeIds, focusNodeIds);
  }

  @override
  int get hashCode =>
      Object.hash(canvasId, kind, seq, Object.hashAll(focusNodeIds));

  @override
  String toString() {
    return 'CanvasAiActivity(canvas=$canvasId, kind=${kind.name}, '
        'focus=$focusNodeIds, seq=$seq)';
  }
}
