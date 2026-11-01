// 职责: 渲染一个 A2UI 界面 — 解析组件树、决定根节点滚动方式，加载失败时只显示局部错误。
// 关联文件:
//   lib/shared/widgets/a2ui/session.dart
//   lib/shared/widgets/a2ui/node_view.dart
//   lib/shared/widgets/a2ui/component.dart
//   lib/shared/components/reveric_placeholder.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/a2ui.json
//   assets/translations/zh-CN/a2ui.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_placeholder.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'component.dart';
import 'node_view.dart';
import 'session.dart';
import 'signal_hook.dart';

/// 向组件 builder 提供所属会话（写回出错上报、action 进行中状态）。
class A2uiSurfaceScope extends InheritedWidget {
  const A2uiSurfaceScope({
    super.key,
    required this.session,
    required super.child,
  });

  final A2uiSurfaceSession session;

  static A2uiSurfaceSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<A2uiSurfaceScope>()?.session;

  @override
  bool updateShouldNotify(A2uiSurfaceScope oldWidget) =>
      !identical(session, oldWidget.session);
}

/// 渲染 [session] 的界面。会话由调用方创建和释放，且必须晚于本组件释放。
///
/// 有界高度下根节点自带滚动：根为 `List` 时由列表按需构建，其余根节点包一层
/// [SingleChildScrollView]；高度无界时（如嵌在聊天卡片里）按内容高度排版。
class A2uiSurfaceView extends HookWidget {
  const A2uiSurfaceView({
    super.key,
    required this.session,
    this.padding = EdgeInsets.zero,
    this.showErrorDetails = false,
  });

  final A2uiSurfaceSession session;
  final EdgeInsetsGeometry padding;

  /// 在错误占位中附带底层错误码与原因，仅用于调试预览。
  final bool showErrorDetails;

  @override
  Widget build(BuildContext context) {
    final error = useValueListenable(session.error);
    final surface = session.surface;
    final resolver = useMemoized(
      () => surface == null ? null : NodeResolver<A2uiComponent>(surface),
      [surface],
    );
    useEffect(() => resolver?.dispose, [resolver]);

    if (error != null) {
      return _SurfaceError(error: error, showDetails: showErrorDetails);
    }
    if (resolver == null) {
      return const SizedBox.shrink();
    }
    return A2uiSurfaceScope(
      session: session,
      child: KeyedSubtree(
        key: ObjectKey(surface),
        child: _SurfaceRoot(resolver: resolver, padding: padding),
      ),
    );
  }
}

class _SurfaceRoot extends HookWidget {
  const _SurfaceRoot({required this.resolver, required this.padding});

  final NodeResolver<A2uiComponent> resolver;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final root = useSignal(resolver.rootNode);
    if (root == null) {
      return const A2uiPendingIndicator();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = A2uiNodeView(root);
        if (!constraints.hasBoundedHeight) {
          return Padding(padding: padding, child: content);
        }
        if (root.type == 'List') {
          return Padding(padding: padding, child: content);
        }
        return SingleChildScrollView(padding: padding, child: content);
      },
    );
  }
}

class _SurfaceError extends StatelessWidget {
  const _SurfaceError({required this.error, required this.showDetails});

  final A2uiSessionException error;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        child: RevericPlaceholder.error(
          title: context.t(LocaleKeys.a2uiSurfaceUnavailableTitle),
          description: context.t(LocaleKeys.a2uiSurfaceUnavailableDescription),
          compact: true,
          action: showDetails
              ? SelectableText(
                  '${error.code}: ${error.message}',
                  style: typo.mono.copyWith(color: colors.textMuted),
                )
              : null,
        ),
      ),
    );
  }
}
