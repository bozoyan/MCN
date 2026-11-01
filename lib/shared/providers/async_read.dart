// 职责: 在异步取值或资源操作期间持有 Provider 订阅，结束后归还生命周期。
// 关联文件:
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/providers/official_skill_sync_providers.dart
//   lib/shared/providers/todo_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

extension AsyncContainerRead on ProviderContainer {
  /// 只在等待数据快照期间保活；返回的 client/DB 等资源仍需由调用方另持 lease。
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) =>
      withProvider(provider, (future) => future);

  /// 资源对象在整个 action 期间可用，成功和异常出口均释放订阅。
  Future<R> withProvider<T, R>(
    ProviderListenable<T> provider,
    Future<R> Function(T value) action,
  ) async {
    final subscription = listen(provider, (_, _) {});
    try {
      return await action(subscription.read());
    } finally {
      subscription.close();
    }
  }
}

extension AsyncRefRead on Ref {
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) =>
      container.readFuture(provider);
}

extension AsyncWidgetRefRead on WidgetRef {
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) =>
      ProviderScope.containerOf(context, listen: false).readFuture(provider);
}
