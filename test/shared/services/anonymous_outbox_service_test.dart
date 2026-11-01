// 职责: 验证匿名 Outbox 只有收到 204 才删除事件，并重试失败批次。
// 关联文件:
//   lib/shared/services/anonymous_outbox_service.dart
//   lib/shared/database/daos/anonymous_outbox_dao.dart
//   lib/shared/database/app_database.dart

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/anonymous_outbox_service.dart';

void main() {
  late AppDatabase database;
  late _RecordingClient httpClient;
  late AnonymousOutboxService outbox;

  setUp(() {
    database = AppDatabase.forTest(NativeDatabase.memory());
    httpClient = _RecordingClient();
    outbox = AnonymousOutboxService(
      database: database,
      httpClient: httpClient,
      getBaseUrl: () => 'https://anonymous.example',
      getEnabled: () => true,
      autoFlush: false,
    );
  });

  tearDown(() async {
    outbox.dispose();
    httpClient.close();
    await database.close();
  });

  test(
    'disabled reporting neither queues new events nor sends pending events',
    () async {
      var enabled = true;
      outbox.dispose();
      outbox = AnonymousOutboxService(
        database: database,
        httpClient: httpClient,
        getBaseUrl: () => 'https://anonymous.example',
        getEnabled: () => enabled,
        autoFlush: false,
      );
      Future<void> enqueue(String id) => outbox.enqueue(
        AnonymousOutboxEventInput(
          eventId: id,
          channel: AnonymousOutboxChannel.trace,
          endpoint: AnonymousOutboxEndpoint.trace,
          deviceId: 'device',
          occurredAt: DateTime.now().toUtc(),
          payload: {'event_id': id},
        ),
      );

      await enqueue('pending');
      enabled = false;
      await enqueue('disabled');
      await outbox.flush();
      expect(httpClient.requests, isEmpty);
      final pending = await database
          .select(database.anonymousOutboxEvents)
          .get();
      expect(pending, hasLength(1));
      expect(pending.single.eventId, 'pending');

      enabled = true;
      await outbox.flush();
      expect(httpClient.requests, hasLength(1));
      expect(
        await database.select(database.anonymousOutboxEvents).get(),
        isEmpty,
      );
    },
  );

  test(
    'transactional events are sent only after commit, never on rollback',
    () async {
      outbox.dispose();
      outbox = AnonymousOutboxService(
        database: database,
        httpClient: httpClient,
        getBaseUrl: () => 'https://anonymous.example',
        getEnabled: () => true,
      );
      Future<void> enqueue(String id) => outbox.enqueue(
        AnonymousOutboxEventInput(
          eventId: id,
          channel: AnonymousOutboxChannel.trace,
          endpoint: AnonymousOutboxEndpoint.trace,
          deviceId: 'device',
          occurredAt: DateTime.now().toUtc(),
          payload: {'event_id': id},
        ),
      );
      await expectLater(
        database.transaction(() async {
          await enqueue('rolled-back');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(httpClient.requests, isEmpty);
          throw StateError('business write failed');
        }),
        throwsStateError,
      );
      await outbox.flush();
      expect(httpClient.requests, isEmpty);
      await database.transaction(() async {
        await enqueue('committed');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(httpClient.requests, isEmpty);
      });
      // flush coalesces concurrent requests; the queued follow-up can begin
      // after the Future returned by the previous flush has completed.
      await _waitFor(() => httpClient.requests.length == 1);
      await outbox.flush();
      expect(httpClient.requests, hasLength(1));
      expect(httpClient.requests.single.body, contains('committed'));
    },
  );

  test(
    'duplicate event keeps its first payload, timestamp and retry backoff',
    () async {
      final firstTime = DateTime.utc(2026, 9, 20);
      Future<void> enqueue(DateTime at) => outbox.enqueue(
        AnonymousOutboxEventInput(
          eventId: 'stable-event',
          channel: AnonymousOutboxChannel.trace,
          endpoint: AnonymousOutboxEndpoint.trace,
          deviceId: 'device',
          occurredAt: at,
          payload: {'occurred_at': at.toIso8601String()},
        ),
      );
      await enqueue(firstTime);
      final retryAt = DateTime.now().toUtc().add(const Duration(hours: 1));
      final original = await database
          .select(database.anonymousOutboxEvents)
          .getSingle();
      await database.anonymousOutboxDao.scheduleRetry(
        ids: [original.id],
        nextRetryAt: retryAt,
      );
      await Future.wait([
        enqueue(firstTime.add(const Duration(days: 1))),
        enqueue(firstTime),
      ]);
      final row = await database
          .select(database.anonymousOutboxEvents)
          .getSingle();
      expect(row.eventId, original.eventId);
      expect(row.payloadJson, original.payloadJson);
      expect(row.occurredAt, original.occurredAt);
      expect(row.attemptCount, 1);
      expect(
        row.nextRetryAt.millisecondsSinceEpoch ~/ 1000,
        retryAt.millisecondsSinceEpoch ~/ 1000,
      );
    },
  );

  test('trace batch preserves JSON and deletes only after 204', () async {
    httpClient.statusCode = 500;
    await outbox.enqueue(
      AnonymousOutboxEventInput(
        eventId: 'b7f9cceb-9158-4ec4-a0bc-6c0ea210c0d8',
        channel: AnonymousOutboxChannel.trace,
        endpoint: AnonymousOutboxEndpoint.trace,
        deviceId: 'derived-device-id',
        occurredAt: DateTime.utc(2026, 7, 15, 12),
        payload: {
          'event_id': 'b7f9cceb-9158-4ec4-a0bc-6c0ea210c0d8',
          'event_type': 'turn_end',
        },
      ),
    );
    await outbox.flush();

    final failed = await database
        .select(database.anonymousOutboxEvents)
        .getSingle();
    expect(failed.attemptCount, 1);
    expect(httpClient.requests, hasLength(1));

    final firstRequest = httpClient.requests.single;
    final rawBody = firstRequest.body;
    expect(firstRequest.headers['X-Product-Code'], 'writer');
    expect(jsonDecode(rawBody), {
      'events': [
        {
          'event_id': 'b7f9cceb-9158-4ec4-a0bc-6c0ea210c0d8',
          'event_type': 'turn_end',
        },
      ],
    });

    httpClient.statusCode = 204;
    await database.anonymousOutboxDao.scheduleRetry(
      ids: [1],
      nextRetryAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    await outbox.flush();

    final remaining = await database
        .select(database.anonymousOutboxEvents)
        .get();
    expect(remaining, isEmpty);
    expect(httpClient.requests, hasLength(2));
  });

  test('dispose after 204 still deletes the acknowledged batch', () async {
    httpClient.statusCode = 204;
    final responseGate = Completer<void>();
    httpClient.responseGate = responseGate.future;
    await outbox.enqueue(
      AnonymousOutboxEventInput(
        channel: AnonymousOutboxChannel.trace,
        endpoint: AnonymousOutboxEndpoint.trace,
        deviceId: 'dispose-race-device',
        occurredAt: DateTime.utc(2026, 7, 15, 12),
        payload: {'event_type': 'turn_end'},
      ),
    );

    final flushFuture = outbox.flush();
    await _waitFor(() => httpClient.requests.length == 1);
    outbox.dispose();
    responseGate.complete();
    await flushFuture;

    final remaining = await database
        .select(database.anonymousOutboxEvents)
        .get();
    expect(remaining, isEmpty);
  });

  test('trace capacity evicts its oldest event without affecting usage', () async {
    for (var index = 0; index < 4097; index += 1) {
      await outbox.enqueue(
        AnonymousOutboxEventInput(
          eventId:
              '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
          channel: AnonymousOutboxChannel.trace,
          endpoint: AnonymousOutboxEndpoint.trace,
          deviceId: 'device-$index',
          occurredAt: DateTime.utc(2026, 7, 15),
          payload: {'event_id': 'event-$index'},
        ),
      );
    }
    await outbox.enqueue(
      AnonymousOutboxEventInput(
        channel: AnonymousOutboxChannel.usage,
        endpoint: AnonymousOutboxEndpoint.usage,
        deviceId: 'usage-device',
        occurredAt: DateTime.utc(2026, 7, 15),
        payload: {'event_type': 'app_launch'},
      ),
    );

    final traceCount = await database
        .customSelect(
          "SELECT COUNT(*) AS event_count FROM anonymous_outbox_events WHERE channel = 'trace'",
        )
        .getSingle();
    final usageCount = await database
        .customSelect(
          "SELECT COUNT(*) AS event_count FROM anonymous_outbox_events WHERE channel = 'usage'",
        )
        .getSingle();

    expect(traceCount.read<int>('event_count'), 4096);
    expect(usageCount.read<int>('event_count'), 1);
  });

  test('retries a failed batch after its scheduled backoff', () async {
    httpClient.statusCode = 500;
    await outbox.enqueue(
      AnonymousOutboxEventInput(
        channel: AnonymousOutboxChannel.usage,
        endpoint: AnonymousOutboxEndpoint.usage,
        deviceId: 'retry-device',
        occurredAt: DateTime.utc(2026, 7, 15, 12),
        payload: {'event_type': 'app_launch'},
      ),
    );

    await outbox.flush();
    expect(httpClient.requests, hasLength(1));

    httpClient.statusCode = 204;
    await _waitFor(() => httpClient.requests.length == 2);

    final remaining = await database
        .select(database.anonymousOutboxEvents)
        .get();
    expect(remaining, isEmpty);
  });

  test(
    'dispose prevents late enqueue and flush from touching the database',
    () async {
      outbox.dispose();

      await expectLater(
        outbox.enqueue(
          AnonymousOutboxEventInput(
            channel: AnonymousOutboxChannel.trace,
            endpoint: AnonymousOutboxEndpoint.trace,
            deviceId: 'disposed-device',
            occurredAt: DateTime.utc(2026, 7, 15),
            payload: {'event_type': 'turn_end'},
          ),
        ),
        completes,
      );
      await expectLater(outbox.flush(), completes);

      final remaining = await database
          .select(database.anonymousOutboxEvents)
          .get();
      expect(remaining, isEmpty);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _RecordedRequest {
  const _RecordedRequest({required this.headers, required this.body});

  final Map<String, String> headers;
  final String body;
}

class _RecordingClient extends http.BaseClient {
  int statusCode = 204;
  Future<void>? responseGate;
  final requests = <_RecordedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    requests.add(_RecordedRequest(headers: request.headers, body: body));
    final gate = responseGate;
    if (gate != null) {
      await gate;
    }
    return http.StreamedResponse(Stream.value(utf8.encode('')), statusCode);
  }
}
