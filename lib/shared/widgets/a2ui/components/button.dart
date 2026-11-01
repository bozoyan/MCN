// 职责: A2UI Button 的 builder — 按子组件（Text 或 Icon）选择 Reveric 按钮，处理 checks 禁用与 action 进行中状态。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/widgets/a2ui/session.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/components/reveric_icon_button.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_button.dart';
import '../../../components/reveric_icon_button.dart';
import '../component.dart';
import '../signal_hook.dart';
import '../surface_view.dart';
import 'display.dart';
import 'field_frame.dart';

Widget buildButton(
  BuildContext context,
  A2uiNode node,
  A2uiProps props,
  A2uiChildBuilder buildChild,
) {
  final accessibility = props.value('accessibility');
  return _A2uiButton(
    componentId: node.componentId,
    labelNode: props.child('child'),
    variant: props.string('variant'),
    action: props.isValid ? props.action('action') : null,
    invalidReason: props.isValid
        ? null
        : a2uiCheckMessage(context, props.validationErrors.firstOrNull),
    tooltip: accessibility is Map
        ? A2uiProps.asString(accessibility['label'])
        : null,
  );
}

final _noPending = ValueNotifier<List<String>>(const []);

class _A2uiButton extends HookWidget {
  const _A2uiButton({
    required this.componentId,
    required this.labelNode,
    required this.variant,
    required this.action,
    required this.invalidReason,
    required this.tooltip,
  });

  final String componentId;

  /// 按钮的子组件：Text 作为文字按钮，Icon 作为图标按钮。
  final A2uiNode? labelNode;
  final String? variant;
  final Future<void> Function()? action;
  final String? invalidReason;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final session = A2uiSurfaceScope.maybeOf(context);
    final pending = useValueListenable(session?.pendingSources ?? _noPending);
    // 子组件的文字可能绑定页面数据，订阅它以便标签随数据刷新。
    final labelProps = A2uiProps(useSignal(labelNode?.props ?? _emptyProps));
    final loading = pending.contains(componentId);
    final action = this.action;
    final VoidCallback? onPressed = action == null || loading
        ? null
        : () => unawaited(action());

    final Widget button;
    if (labelNode?.type == 'Icon') {
      button = RevericIconButton(
        icon: a2uiIconAsset(labelProps.string('name')),
        tooltip: tooltip ?? '',
        onPressed: onPressed,
      );
    } else {
      final label = labelProps.string('text') ?? '';
      button = switch (variant) {
        'primary' => RevericButton.primary(
          label: label,
          onPressed: onPressed,
          loading: loading,
        ),
        'borderless' => RevericButton.text(
          label: label,
          onPressed: onPressed,
          loading: loading,
        ),
        _ => RevericButton.secondary(
          label: label,
          onPressed: onPressed,
          loading: loading,
        ),
      };
    }
    final reason = invalidReason;
    // 按钮保持自身宽度，不被 Column 的 stretch 拉满整行。
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: reason == null ? button : Tooltip(message: reason, child: button),
    );
  }
}

final _emptyProps = signal<NodeProps>(const {});
