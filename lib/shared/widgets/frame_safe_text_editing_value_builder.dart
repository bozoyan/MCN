// 职责: 文本编辑值监听构建器 — 在安全帧阶段响应 TextEditingController 变化以避免构建中调度新帧。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef TextEditingValueWidgetBuilder =
    Widget Function(
      BuildContext context,
      TextEditingValue value,
      Widget? child,
    );

class FrameSafeTextEditingValueBuilder extends StatefulWidget {
  const FrameSafeTextEditingValueBuilder({
    super.key,
    required this.controller,
    required this.builder,
    this.child,
  });

  final TextEditingController controller;
  final TextEditingValueWidgetBuilder builder;
  final Widget? child;

  @override
  State<FrameSafeTextEditingValueBuilder> createState() =>
      _FrameSafeTextEditingValueBuilderState();
}

class _FrameSafeTextEditingValueBuilderState
    extends State<FrameSafeTextEditingValueBuilder> {
  late TextEditingValue _value;
  bool _postFrameRebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _value = widget.controller.value;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant FrameSafeTextEditingValueBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _value = widget.controller.value;
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    _value = widget.controller.value;
    if (!mounted) {
      return;
    }
    if (_isPersistentFrameCallback) {
      if (_postFrameRebuildScheduled) {
        return;
      }
      _postFrameRebuildScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _postFrameRebuildScheduled = false;
        if (!mounted) {
          return;
        }
        setState(() {
          _value = widget.controller.value;
        });
      });
      return;
    }
    setState(() {});
  }

  bool get _isPersistentFrameCallback {
    return SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value, widget.child);
  }
}
