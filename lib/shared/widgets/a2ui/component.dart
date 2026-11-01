// 职责: 定义 A2UI 组件目录条目（Schema + Flutter builder）与组件属性的类型化读取。
// 关联文件:
//   lib/shared/widgets/a2ui/catalog.dart
//   lib/shared/widgets/a2ui/node_view.dart
//   lib/shared/widgets/a2ui/session.dart

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter/widgets.dart';

typedef A2uiNode = ComponentNode<A2uiComponent>;

typedef A2uiChildBuilder = Widget Function(A2uiNode child);

typedef A2uiComponentBuilder =
    Widget Function(
      BuildContext context,
      A2uiNode node,
      A2uiProps props,
      A2uiChildBuilder buildChild,
    );

typedef A2uiCatalog = Catalog<A2uiComponent, FunctionImplementation>;

/// 组件目录中的一个组件：名称和属性 Schema 交给 `a2ui_core` 校验，
/// builder 负责把已解析的节点渲染为 Flutter Widget。
class A2uiComponent extends ComponentApi {
  const A2uiComponent({
    required super.name,
    required super.schema,
    required this.builder,
    super.allowedChildren,
  });

  final A2uiComponentBuilder builder;
}

/// 以节点实例 ID 作为 key，数据模板重排时保留对应子树的状态。
class A2uiNodeKey extends ValueKey<String> {
  const A2uiNodeKey(super.value);
}

/// 已解析节点属性的类型化读取；绑定值会先解包。
extension type const A2uiProps(NodeProps _props) implements NodeProps {
  static Object? unwrap(Object? value) =>
      value is ResolvedBinding<Object?> ? value.value : value;

  static String? asString(Object? value) => switch (unwrap(value)) {
    final String s => s,
    final int n => '$n',
    final num n => n == n.truncate() ? '${n.truncate()}' : '$n',
    final bool b => '$b',
    _ => null,
  };

  static double? asNumber(Object? value) => switch (unwrap(value)) {
    final num n => n.toDouble(),
    _ => null,
  };

  /// v1.0 校验函数返回 [ValidationResult]，这里按其有效性读取。
  static bool? asBoolean(Object? value) => switch (unwrap(value)) {
    final bool b => b,
    final Object? other => ValidationResult.validityOf(other),
  };

  Object? value(String key) => unwrap(this[key]);

  String? string(String key) => asString(this[key]);

  double? number(String key) => asNumber(this[key]);

  bool? boolean(String key) => asBoolean(this[key]);

  List<Object?> list(String key) => switch (value(key)) {
    final List<Object?> l => l,
    _ => const [],
  };

  /// 只有绑定到数据路径的属性可以写回。
  WritableBinding<Object?>? writable(String key) => switch (this[key]) {
    final WritableBinding<Object?> b => b,
    _ => null,
  };

  /// 调用时才按当时的页面数据解析 action context。
  Future<void> Function()? action(String key) => switch (this[key]) {
    final Future<void> Function() a => a,
    _ => null,
  };

  A2uiNode? child(String key) => switch (this[key]) {
    final A2uiNode n => n,
    _ => null,
  };

  List<A2uiNode> children(String key) => switch (this[key]) {
    final List<Object?> l => l.whereType<A2uiNode>().toList(growable: false),
    _ => const [],
  };

  /// 任一 error 级别的 check 未通过时为 false。
  bool get isValid => this['isValid'] != false;

  List<String> get validationErrors => switch (this['validationErrors']) {
    final List<Object?> l => l.whereType<String>().toList(growable: false),
    _ => const [],
  };
}
