// 职责: 串行投递匿名用量和诊断事件 的本地持久化 Outbox。
// 关联文件:
//   lib/shared/database/daos/anonymous_outbox_dao.dart
//   lib/shared/services/ai/trace_reporter_service.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/service-naming.md

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../database/app_database.dart';
import '../logger/app_logger.dart';

final _log = AppLogger.forModule('AnonymousOutbox');

enum AnonymousOutboxChannel {
  usage(priority: 1, maxEvents: 1024),
  trace(priority: 2, maxEvents: 4096),
  toolError(priority: 3, maxEvents: 2048),
  requestError(priority: 4, maxEvents: 2048);

  const AnonymousOutboxChannel({
    required this.priority,
    required this.maxEvents,
  });

  final int priority;
  final int maxEvents;
}

enum AnonymousOutboxEndpoint {
  // Endpoint paths are relative to the configured anonymous reporting URL.
  usage(''),
  trace(''),
  toolError(''),
  requestError('');

  const AnonymousOutboxEndpoint(this.path);

  final String path;
}

class AnonymousOutboxEventInput {
  const AnonymousOutboxEventInput({
    required this.channel,
    required this.endpoint,
    required this.deviceId,
    required this.payload,
    required this.occurredAt,
    this.eventId,
  });

  final AnonymousOutboxChannel channel;
  final AnonymousOutboxEndpoint endpoint;
  final String deviceId;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;
  final String? eventId;
}

/// 将 endpoint 专属事件持久化后按固定协议批量上报。
class AnonymousOutboxService {
  AnonymousOutboxService({
    required this._database,
    required this._httpClient,
    required this._getBaseUrl,
    required this._getEnabled,
    this._autoFlush = true,
  }) : _dispatchZone = Zone.current;

  final AppDatabase _database;
  final http.Client _httpClient;
  final String? Function() _getBaseUrl;
  final bool Function() _getEnabled;
  final bool _autoFlush;
  // 服务在事务外创建；后台投递不得继承 enqueue 调用方的 Drift 事务，
  // 否则可能在业务提交前发出事件，或在事务结束后继续使用已关闭事务。
  final Zone _dispatchZone;

  Future<void>? _activeFlush;
  Timer? _retryTimer;
  bool _flushRequested = false;
  bool _disposed = false;

  int get _batchSize => kDebugMode ? 1 : 100;

  /// 写入成功后触发后台 flush；调用方不必等待网络完成。
  Future<void> enqueue(AnonymousOutboxEventInput input) async {
    if (_disposed) {
      if (_log.isDebugEnabled) {
        _log.debug(
          'enqueue skipped: disposed=true channel=${input.channel.name}',
        );
      }
      return;
    }
    if (!_getEnabled()) {
      if (_log.isDebugEnabled) {
        _log.debug(
          'enqueue skipped: reporting disabled channel=${input.channel.name}',
        );
      }
      return;
    }

    try {
      await _database.anonymousOutboxDao.enqueue(
        eventId: input.eventId,
        channel: input.channel.name,
        priority: input.channel.priority,
        endpoint: input.endpoint.name,
        productCode: revericProductCode,
        deviceId: input.deviceId,
        payloadJson: jsonEncode(input.payload),
        occurredAt: input.occurredAt,
      );
      if (_disposed) {
        return;
      }
      await _database.anonymousOutboxDao.evictExcess(
        channel: input.channel.name,
        maxEvents: input.channel.maxEvents,
      );
    } catch (error, stackTrace) {
      _log.warning(
        '[DB] table=anonymous_outbox_events operation=ENQUEUE '
        'eventId=${input.eventId} error=$error\n$stackTrace',
      );
      return;
    }
    if (_autoFlush && !_disposed) {
      _dispatchZone.run(() => unawaited(flush()));
    }
  }

  /// 串行投递所有当前可重试的分组批次。
  Future<void> flush() {
    if (_disposed) {
      return Future<void>.value();
    }
    _retryTimer?.cancel();
    _retryTimer = null;

    final active = _activeFlush;
    if (active != null) {
      _flushRequested = true;
      return active;
    }

    final future = _flushLoop().catchError((error, stackTrace) {
      _log.warning('flush loop stopped unexpectedly error=$error\n$stackTrace');
    });
    _activeFlush = future;
    return future.whenComplete(() {
      _activeFlush = null;
      if (_flushRequested) {
        _flushRequested = false;
        unawaited(flush());
      }
    });
  }

  Future<void> _flushLoop() async {
    if (!_getEnabled()) {
      _log.debug('flush skipped: reporting disabled');
      return;
    }

    final baseUrl = _getBaseUrl()?.trim();
    if (baseUrl == null || baseUrl.isEmpty) {
      _log.warning('flush skipped: anonymous reporting base URL is empty');
      return;
    }

    while (!_disposed) {
      late final List<AnonymousOutboxEvent> batch;
      try {
        batch = await _database.anonymousOutboxDao.nextReadyBatch(
          now: DateTime.now().toUtc(),
          limit: _batchSize,
        );
      } catch (error, stackTrace) {
        _log.warning(
          '[DB] table=anonymous_outbox_events operation=SELECT_READY '
          'error=$error\n$stackTrace',
        );
        return;
      }
      if (batch.isEmpty) {
        await _scheduleNextFlush();
        return;
      }

      final accepted = await _sendBatch(baseUrl, batch);
      final ids = batch.map((event) => event.id).toList(growable: false);
      if (accepted) {
        try {
          await _database.anonymousOutboxDao.deleteBatch(ids);
        } catch (error, stackTrace) {
          _log.warning(
            '[DB] table=anonymous_outbox_events operation=DELETE_BATCH '
            'ids=$ids error=$error\n$stackTrace',
          );
          return;
        }
        continue;
      }
      if (_disposed) {
        return;
      }

      final maxAttempts = batch.fold<int>(
        0,
        (value, event) =>
            event.attemptCount > value ? event.attemptCount : value,
      );
      final delaySeconds = 1 << maxAttempts.clamp(0, 8);
      try {
        await _database.anonymousOutboxDao.scheduleRetry(
          ids: ids,
          nextRetryAt: DateTime.now().toUtc().add(
            Duration(seconds: delaySeconds),
          ),
        );
      } catch (error, stackTrace) {
        _log.warning(
          '[DB] table=anonymous_outbox_events operation=SCHEDULE_RETRY '
          'ids=$ids error=$error\n$stackTrace',
        );
        return;
      }
    }
  }

  Future<void> _scheduleNextFlush() async {
    if (_disposed) {
      return;
    }
    _retryTimer?.cancel();
    late final DateTime? nextRetryAt;
    try {
      nextRetryAt = await _database.anonymousOutboxDao.nextScheduledAt();
    } catch (error, stackTrace) {
      _log.warning(
        '[DB] table=anonymous_outbox_events operation=SELECT_NEXT_RETRY '
        'error=$error\n$stackTrace',
      );
      _retryTimer = null;
      return;
    }
    if (nextRetryAt == null) {
      _retryTimer = null;
      return;
    }

    final delay = nextRetryAt.difference(DateTime.now().toUtc());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_disposed) {
        return;
      }
      _retryTimer = null;
      unawaited(flush());
    });
  }

  Future<bool> _sendBatch(
    String baseUrl,
    List<AnonymousOutboxEvent> batch,
  ) async {
    final first = batch.first;
    final endpoint = AnonymousOutboxEndpoint.values.byName(first.endpoint);
    final events = [
      for (final event in batch)
        jsonDecode(event.payloadJson) as Map<String, dynamic>,
    ];
    final body = jsonEncode({'events': events});
    final headers = Map<String, String>.from(revericApiHeaders);

    final url = '${baseUrl.replaceFirst(RegExp(r'/$'), '')}${endpoint.path}';
    try {
      final response = await _httpClient
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 204) {
        if (_log.isDebugEnabled) {
          _log.debug(
            'flush accepted endpoint=${endpoint.name} count=${batch.length}',
          );
        }
        return true;
      }
      _log.warning(
        'flush rejected endpoint=${endpoint.name} count=${batch.length} '
        'status=${response.statusCode} body=${response.body}',
      );
    } catch (error, stackTrace) {
      _log.warning(
        'flush failed endpoint=${endpoint.name} count=${batch.length} '
        'error=$error\n$stackTrace',
      );
    }
    return false;
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
