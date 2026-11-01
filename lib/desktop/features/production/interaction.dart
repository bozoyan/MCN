// 职责: 协调制作画布的外部编辑焦点、多选状态和整组拖动提交。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/third/flow/vyuh_node_flow.dart
import 'package:flutter/widgets.dart';

import '../../../third/flow/vyuh_node_flow.dart' as flow;

class ProductionBoardInteraction {
  ProductionBoardInteraction(this.controller);

  final flow.NodeFlowController<String, String> controller;
  String? focused;
  String? pendingFocus;
  Map<String, String> sceneForNode = const {};
  final _dragged = <String>{};
  Map<String, String> storyboardParents = const {};

  void restoreFixedMembers() {
    for (final entry in storyboardParents.entries) {
      if (!controller.selectedNodeIds.contains(entry.value)) {
        final at = controller.interaction.dragStartPositions[entry.key];
        if (at != null) {
          controller.setNodePosition(entry.key, at);
        }
      }
    }
  }

  void syncFocus(String? selected) {
    if (controller.draggedNodeId != null) {
      focused = selected;
      pendingFocus = null;
      return;
    }
    // 数据刷新不覆盖框选；外部切换焦点或点选被拒时才重新对齐。
    if (focused == selected && pendingFocus == null) {
      return;
    }
    focused = selected;
    pendingFocus = null;
    controller.clearSelection();
    if (selected != null && controller.getNode(selected) != null) {
      controller.selectNode(selected);
      controller.bringNodeToFront(selected);
    }
  }

  void selectionChanged() {
    // 容器只有被完整框住时才加入框选；只擦过外框应仍能独立选择格子。
    final rectangle = controller.selectionRect?.rect;
    if (controller.isDrawingSelection && rectangle != null) {
      final selected = controller.selectedNodeIds.toSet();
      final filtered = selected.where((id) {
        final node = controller.getNode(id);
        if (node is! flow.GroupNode<String>) {
          return true;
        }
        final frame = node.position.value & node.size.value;
        return rectangle.left <= frame.left &&
            rectangle.top <= frame.top &&
            rectangle.right >= frame.right &&
            rectangle.bottom >= frame.bottom;
      }).toSet();
      if (filtered.length != selected.length) {
        controller.selectNodes(filtered.toList());
      }
    }
    if (controller.isDrawingSelection ||
        controller.selectedNodeIds.length > 1) {
      _selectWholeScenes();
    }
  }

  void _selectWholeScenes() {
    final selected = controller.selectedNodeIds.toSet();
    final scenes = selected.map((id) => sceneForNode[id]).nonNulls.toSet();
    final expanded = {
      ...selected,
      for (final entry in sceneForNode.entries)
        if (scenes.contains(entry.value) &&
            controller.getNode(entry.key) != null)
          entry.key,
    };
    if (expanded.length != selected.length) {
      controller.selectNodes(expanded.toList());
    }
  }

  void startDrag() {
    pendingFocus = null;
    _selectWholeScenes();
    _dragged.clear();
    final positions = Map<String, Offset>.from(
      controller.interaction.dragStartPositions,
    );
    for (final id in controller.selectedNodeIds) {
      final node = controller.getNode(id)!;
      node.isDragging = true;
      if (!storyboardParents.containsKey(id) ||
          controller.selectedNodeIds.contains(storyboardParents[id])) {
        _dragged.add(id);
      }
      if (node is flow.GroupNode<String>) {
        for (final memberId in node.nodeIds) {
          final member = controller.getNode(memberId);
          if (member != null) {
            _dragged.add(memberId);
            positions.putIfAbsent(memberId, () => member.position.value);
          }
        }
      }
      positions.putIfAbsent(id, () => node.position.value);
    }
    // 单节点开始拖动后补齐的场内节点，也必须参与取消回退与批量保存。
    controller.interaction.captureDragStartPositions(positions);
  }

  Map<String, Offset> finishDrag() {
    final positions = <String, Offset>{
      for (final id in _dragged)
        if (controller.getNode(id) case final node?) id: node.position.value,
    };
    // flow 为每个节点调用 onDragStop，整组只提交一次。
    _dragged.clear();
    return positions;
  }

  void cancelDrag() => _dragged.clear();
}
