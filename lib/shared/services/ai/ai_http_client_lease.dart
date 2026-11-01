// 职责: 按 provider 与代理配置共享 http.Client,以引用计数决定关闭时机
// 关联文件:
//   lib/shared/models/ai_provider.dart
//   lib/shared/services/ai/provider_initializer.dart
//   lib/shared/providers/ai_providers.dart

import 'package:http/http.dart' as http;

import '../../models/ai_provider.dart';

/// 一次 http.Client 借用凭证。
///
/// 持有者用完必须 [release]；底层 client 在最后一个持有者释放后才关闭。
class AiHttpClientLease {
  AiHttpClientLease._(this._registry, this._key, this.client);

  final AiHttpClientRegistry _registry;
  final String _key;

  /// 借到的 client。[release] 之后不得再使用。
  final http.Client client;

  bool _released = false;

  /// 归还借用。幂等,重复调用安全。
  void release() {
    if (_released) return;
    _released = true;
    _registry._release(_key);
  }
}

/// 共享 http.Client 的引用计数注册表。
///
/// client 的生命周期由借用方的 [AiHttpClientLease.release] 决定,而不是
/// Riverpod 的 autoDispose 时机。否则 `ref.read` 取得的资源可能在请求仍在运行时
/// 被回收并关闭,进而抛出
/// `ClientException: HTTP request failed. Client is already closed.`。
///
// TODO(http-client-lease): 当前是「消费者持租约、手动 release」的半 RAII 模型。
// 更彻底的做法是让持有 http.Client 的 [AiClient] 自身持租约、在 teardown 时
// release,消费者(runtime / provider)完全不记账。前提是先给 AiClient 建立统一
// 可靠的 dispose 生命周期(现在多处构造、无统一销毁钩子),届时 registry 的
// refCount 可直接绑定 AiClient 实例数,[AiHttpClientLeasePool] / [AiHttpClientLeaseHolder]
// 这些「代消费者记账」的中间层即可删除。
class AiHttpClientRegistry {
  AiHttpClientRegistry({http.Client Function(AiProvider config)? clientFactory})
    : _clientFactory =
          clientFactory ??
          ((config) => config.createProxyClient() ?? http.Client());

  final http.Client Function(AiProvider config) _clientFactory;
  final Map<String, _Entry> _entries = {};

  /// 借用 [config] 对应的 client,引用计数 +1。
  AiHttpClientLease acquire(AiProvider config) {
    final key = _keyFor(config);
    final entry = _entries.putIfAbsent(
      key,
      () => _Entry(_clientFactory(config)),
    );
    entry.refCount++;
    return AiHttpClientLease._(this, key, entry.client);
  }

  void _release(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount > 0) return;
    _entries.remove(key);
    entry.client.close();
  }

  /// key 必须包含代理配置,否则改了代理设置后会复用旧 client,导致新配置不生效。
  /// 这是旧实现里 `ref.watch(aiSettingsProvider)` 重建语义的替代——按配置分桶,
  /// 而不是靠 close 掉在飞的连接来实现配置更新。
  static String _keyFor(AiProvider config) {
    return [
      config.id,
      config.proxyUrl.trim(),
      config.proxyUsername.trim(),
      config.proxyPassword.trim(),
    ].join('\u0000');
  }

  /// 仅供测试断言使用。
  int debugRefCountFor(AiProvider config) =>
      _entries[_keyFor(config)]?.refCount ?? 0;
}

/// 只持有一份租约的槽位,供「反复取用同一 client、但配置可能中途变化」的长生命
/// 周期调用方使用(如定时后台作业)。
///
/// 直接在这类调用方里每次 `acquire` + `ref.onDispose` 会让租约与回调无上限累积;
/// 本类保证任意时刻至多持有一份租约,配置切换时先归还旧的。
class AiHttpClientLeaseHolder {
  AiHttpClientLeaseHolder(this._registry);

  final AiHttpClientRegistry _registry;
  AiHttpClientLease? _lease;
  String? _key;

  /// 取用 [config] 对应的 client;配置变化时自动归还旧租约。
  http.Client clientFor(AiProvider config) {
    final key = AiHttpClientRegistry._keyFor(config);
    if (_lease != null && _key == key) {
      return _lease!.client;
    }
    _lease?.release();
    _key = key;
    _lease = _registry.acquire(config);
    return _lease!.client;
  }

  /// 归还当前租约。幂等。
  void dispose() {
    _lease?.release();
    _lease = null;
    _key = null;
  }
}

/// 多 key 租约池:每个 config 至多持有一份租约,重复取用复用同一份,[dispose]
/// 时一次性全部归还。
///
/// 供「同时使用多个 provider 配置、且生命周期长」的消费者(如聊天 runtime)使用。
/// 这类消费者是单个稳定的长期借用方,一个 config 天然只应算一份租约;若在热路径
/// (每 turn / 每 sub-agent)反复 `acquire` 而不 release,registry 的 refCount 会
/// 退化成「turn 数」而非「存活消费者数」。本池保证按 config 去重,把 refCount 语义
/// 收回正确含义。[dispose] 幂等,归还后可继续复用。
class AiHttpClientLeasePool {
  AiHttpClientLeasePool(this._registry);

  final AiHttpClientRegistry _registry;
  final Map<String, AiHttpClientLease> _leases = {};

  /// 取用 [config] 对应的共享 client;同一 config 复用同一份租约。
  http.Client clientFor(AiProvider config) =>
      (_leases[AiHttpClientRegistry._keyFor(config)] ??= _registry.acquire(
        config,
      )).client;

  /// 归还全部租约。幂等,归还后本池仍可继续 [clientFor]。
  void dispose() {
    for (final lease in _leases.values) {
      lease.release();
    }
    _leases.clear();
  }
}

class _Entry {
  _Entry(this.client);

  final http.Client client;
  int refCount = 0;
}
