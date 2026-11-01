// 职责: 远程控制通用协议 — 定义 channel adapter 抽象基类、消息类型与 adapter 注册表
// 关联文件:
//   lib/shared/services/remote/wechat_adapter.dart
//   lib/shared/services/remote/wechat_api.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:async';

/// Channel type identifier. Extensible — any string is valid so new adapters
/// can register without modifying this definition. Well-known values:
/// 'wechat', 'telegram', 'discord'.
typedef ChannelType = String;

/// Unique address of a user within a channel.
class ChannelAddress {
  const ChannelAddress({
    required this.channelType,
    required this.chatId,
    this.userId,
    this.displayName,
  });

  final ChannelType channelType;

  /// Platform-specific chat/user identifier (e.g. wxid for WeChat).
  final String chatId;

  /// Platform-specific user identifier (optional for group chats).
  final String? userId;

  /// Human-readable name for audit logs.
  final String? displayName;

  SessionKey toSessionKey() =>
      SessionKey(channelType: channelType, chatId: chatId);

  @override
  String toString() =>
      'ChannelAddress($channelType:$chatId${displayName != null ? ' $displayName' : ''})';
}

/// Composite key for routing: channelType + chatId.
class SessionKey {
  const SessionKey({required this.channelType, required this.chatId});

  final ChannelType channelType;
  final String chatId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionKey &&
          channelType == other.channelType &&
          chatId == other.chatId;

  @override
  int get hashCode => Object.hash(channelType, chatId);

  @override
  String toString() => 'SessionKey($channelType:$chatId)';
}

/// Inbound message from an IM channel.
class InboundMessage {
  const InboundMessage({
    required this.messageId,
    required this.address,
    required this.text,
    required this.timestamp,
    this.raw,
  });

  /// Platform-specific message ID (for dedup and reference).
  final String messageId;
  final ChannelAddress address;
  final String text;

  /// Unix epoch milliseconds.
  final int timestamp;

  /// Platform-specific raw update object (for adapter-specific handling).
  final Object? raw;
}

/// Outbound message to send to an IM channel.
class OutboundMessage {
  const OutboundMessage({
    required this.address,
    required this.text,
    this.parseMode = OutboundParseMode.plain,
    this.replyToMessageId,
  });

  final ChannelAddress address;
  final String text;
  final OutboundParseMode parseMode;
  final String? replyToMessageId;
}

/// Text rendering mode for outbound messages.
enum OutboundParseMode { plain, markdown, html }

/// Result of sending a message via an adapter.
class SendResult {
  const SendResult({required this.ok, this.messageId, this.error});

  final bool ok;
  final String? messageId;
  final String? error;

  factory SendResult.success([String? messageId]) =>
      SendResult(ok: true, messageId: messageId);

  factory SendResult.failure(String error) =>
      SendResult(ok: false, error: error);

  @override
  String toString() =>
      ok ? 'SendResult(ok$messageId)' : 'SendResult(error: $error)';
}

/// Status of a single channel adapter.
class AdapterStatus {
  const AdapterStatus({
    required this.channelType,
    required this.running,
    this.connectedAt,
    this.lastMessageAt,
    this.error,
  });

  final ChannelType channelType;
  final bool running;

  /// Unix epoch milliseconds; null when never connected.
  final int? connectedAt;

  /// Unix epoch milliseconds of last inbound/outbound message.
  final int? lastMessageAt;
  final String? error;
}

/// Overall bridge system status.
class BridgeStatus {
  const BridgeStatus({
    required this.running,
    required this.adapters,
    this.startedAt,
  });

  final bool running;
  final List<AdapterStatus> adapters;

  /// Unix epoch milliseconds; null when bridge never started.
  final int? startedAt;
}

/// Capabilities of a channel adapter's streaming preview support.
class PreviewCapabilities {
  const PreviewCapabilities({
    required this.supported,
    this.privateOnly = false,
  });

  final bool supported;
  final bool privateOnly;
}

/// Platform-specific message length limits (chars). Used by adapters for
/// chunking outbound text.
class PlatformLimits {
  const PlatformLimits._();

  static const int wechat = 4000;
  static const int telegram = 4096;
  static const int discord = 2000;
  static const int feishu = 30000;
}

/// Abstract base class for IM channel adapters.
///
/// Each adapter (WeChat, Telegram, ...) extends this class to provide
/// platform-specific message consumption and delivery. The bridge manager
/// (RemoteBridgeService) drives adapters through this uniform interface so
/// that new channels can be added without modifying the orchestrator.
///
/// Contract:
/// - [start] / [stop] / [isRunning] MUST be idempotent.
/// - [consumeOne] MUST never reject; it resolves with `null` when stopped.
/// - [send] MAY reject on transient or permanent failure; caller catches.
abstract class BaseChannelAdapter {
  /// Which channel type this adapter handles.
  ChannelType get channelType;

  /// Start the adapter (connect, begin polling/websocket, etc.).
  /// Calling [start] on an already-running adapter is a no-op.
  Future<void> start();

  /// Stop the adapter gracefully.
  /// Cancels any in-flight long-poll and resolves pending [consumeOne]
  /// callers with `null`. Calling [stop] on an already-stopped adapter is a
  /// no-op.
  Future<void> stop();

  /// Whether the adapter is currently running and consuming messages.
  bool isRunning();

  /// Consume the next inbound message from the internal queue.
  ///
  /// Resolves when a message is available, or `null` if the adapter was
  /// stopped while waiting. Never rejects — callers can `await` without
  /// try/catch.
  Future<InboundMessage?> consumeOne();

  /// Send an outbound message to the channel.
  ///
  /// Handles platform-specific formatting (e.g. chunking) and API calls.
  /// Rejects on transient or permanent failure; callers should catch and
  /// surface. Implementations MUST NOT silently swallow errors.
  Future<SendResult> send(OutboundMessage message);

  /// Validate that the adapter's configuration is complete.
  /// Returns null if valid, or an error message string if invalid.
  String? validateConfig();

  /// Check whether a user is authorized to use this bridge.
  ///
  /// V1 WeChat adapter returns true for all users (known compromise, see
  /// solution doc §10). Override for whitelist-based channels.
  bool isAuthorized(String userId, String chatId) => true;

  // ── Optional hooks ───────────────────────────────────────────────

  /// Called when message processing starts (e.g. typing indicator).
  /// Default: no-op. Override in adapters that support typing.
  Future<void> onMessageStart(String chatId) async {}

  /// Called when message processing ends.
  /// Default: no-op. Override in adapters that support typing.
  Future<void> onMessageEnd(String chatId) async {}

  /// Acknowledge that an update has been fully processed.
  /// Adapters that defer offset commits until after handleMessage should
  /// implement this. Default: no-op.
  void acknowledgeUpdate(Object updateId) {}

  /// Return preview capabilities for a given chat.
  /// Returning null means streaming preview is not available for this chat.
  PreviewCapabilities? getPreviewCapabilities(String chatId) => null;

  /// Current adapter status snapshot.
  AdapterStatus status();
}

// ── Adapter Registry ────────────────────────────────────────────────
//
// Mirrors Claude-to-IM's channel-adapter registry: adapters self-register
// factories so the bridge manager can instantiate channels by type string
// without compile-time coupling.

typedef ChannelAdapterFactory = BaseChannelAdapter Function();

final Map<ChannelType, ChannelAdapterFactory> _adapterFactories = {};

/// Register an adapter factory under [channelType]. Idempotent.
void registerAdapterFactory(
  ChannelType channelType,
  ChannelAdapterFactory factory,
) {
  _adapterFactories[channelType] = factory;
}

/// Create an adapter by channel type, or null if none registered.
BaseChannelAdapter? createAdapter(ChannelType channelType) {
  final factory = _adapterFactories[channelType];
  return factory?.call();
}

/// List all registered channel types.
List<ChannelType> getRegisteredAdapterTypes() =>
    _adapterFactories.keys.toList(growable: false);

/// Reset the registry (test-only).
void resetAdapterRegistry() => _adapterFactories.clear();
