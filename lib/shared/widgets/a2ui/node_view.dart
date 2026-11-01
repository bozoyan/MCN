// 职责: 渲染单个 A2UI 节点 — 订阅节点属性，变化时只重建该节点，并处理未就绪与无效节点。
// 关联文件:
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/widgets/a2ui/signal_hook.dart
//   lib/shared/widgets/a2ui/surface_view.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/a2ui.json
//   assets/translations/zh-CN/a2ui.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_spinner.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'component.dart';
import 'signal_hook.dart';

class A2uiNodeView extends HookWidget {
  A2uiNodeView(this.node) : super(key: A2uiNodeKey(node.instanceId));

  final A2uiNode node;

  @override
  Widget build(BuildContext context) {
    final props = useSignal(node.props);
    return switch (node.state) {
      NodeState.resolved => _buildResolved(context, A2uiProps(props)),
      NodeState.pending => const A2uiPendingIndicator(),
      // 未知类型与循环引用已被加载校验拦截；这里只兜住 Agent 增量推送中的过渡状态。
      _ => const _UnavailableComponent(),
    };
  }

  Widget _buildResolved(BuildContext context, A2uiProps props) {
    final accessibility = props.value('accessibility');
    String? text(String key) {
      final value = accessibility is Map
          ? A2uiProps.asString(accessibility[key])
          : null;
      return value == null || value.isEmpty ? null : value;
    }

    final label = text('label');
    final description = text('description');
    return Semantics(
      container: label != null || description != null,
      label: label,
      hint: description,
      // 组件类型变化时实例 ID 不变，用实现对象区分子树。
      child: KeyedSubtree(
        key: ObjectKey(node.impl),
        child: node.impl!.builder(context, node, props, A2uiNodeView.new),
      ),
    );
  }
}

/// 节点或界面尚未就绪时的小尺寸占位。
class A2uiPendingIndicator extends StatelessWidget {
  const A2uiPendingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.xxs),
        child: SizedBox.square(
          dimension: 16,
          child: RevericSpinner(color: colors.textMuted),
        ),
      ),
    );
  }
}

class _UnavailableComponent extends StatelessWidget {
  const _UnavailableComponent();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      context.t(LocaleKeys.a2uiComponentUnavailable),
      style: typo.uiSmall.copyWith(color: colors.error),
    );
  }
}
