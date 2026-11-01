// 职责: 验证广场目录解析、有效缓存保护和单次刷新状态。
// 关联文件:
//   lib/shared/models/marketplace_agent_skill.dart
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/marketplace_agent_skill.dart';
import 'package:reveric/shared/providers/agent_skill_catalog_providers.dart';
import 'package:reveric/shared/services/agent_skill_catalog_service.dart';

const _entry = {
  'name': 'Dialogue',
  'description': 'Revise a scene',
  'url': 'https://github.com/example/dialogue',
  'when_to_use': 'After drafting',
  'category': 'Writing',
  'tags': ['dialogue'],
};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function() respond;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async => respond();
  @override
  void close({bool force = false}) {
    closed = true;
  }
}

class _ControlledService extends AgentSkillCatalogService {
  final started = Completer<void>();
  Completer<List<MarketplaceAgentSkill>> result = Completer();
  int calls = 0;
  @override
  Future<List<MarketplaceAgentSkill>?> readMarketplaceCache() async =>
      MarketplaceAgentSkill.parseCatalog([_entry]);
  @override
  Future<List<MarketplaceAgentSkill>> listMarketplace() {
    calls++;
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
  }
}

void main() {
  test(
    'each catalog refresh acquires and closes its configured client',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'marketplace-factory-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final adapters = <_Adapter>[];
      final service = AgentSkillCatalogService(
        cacheDirectory: () async => dir,
        createClient: () async {
          final adapter = _Adapter(
            () => ResponseBody.fromString(jsonEncode([_entry]), 200),
          );
          adapters.add(adapter);
          return Dio()..httpClientAdapter = adapter;
        },
      );
      addTearDown(service.dispose);
      await service.listMarketplace();
      await service.listMarketplace();
      expect(adapters, hasLength(2));
      expect(adapters.every((adapter) => adapter.closed), isTrue);
      final failing = AgentSkillCatalogService(
        createClient: () async => throw const FormatException('bad proxy'),
      );
      await expectLater(failing.listMarketplace(), throwsFormatException);
    },
  );

  test('catalog accepts resources and searches when_to_use', () {
    final rows = MarketplaceAgentSkill.parseCatalog([
      _entry,
      {..._entry, 'url': 'https://example.com/guide', 'name': 'Guide'},
    ]);
    expect(rows.first.matches('AFTER'), isTrue);
    expect(rows.first.canImport, isTrue);
    expect(rows.last.canImport, isFalse);
    expect(MarketplaceAgentSkill.parseCatalog([]), isEmpty);
    for (final changed in [
      {'name': ''},
      {
        'tags': [7],
      },
      {'when_to_use': null},
      {'url': 'http://example.com'},
      {'url': 'https://secret@example.com'},
    ]) {
      expect(
        () => MarketplaceAgentSkill.parseCatalog([
          {..._entry, ...changed},
        ]),
        throwsFormatException,
      );
    }
    expect(
      () => MarketplaceAgentSkill.parseCatalog([_entry, _entry]),
      throwsFormatException,
    );
  });

  test(
    'bad responses and oversized streams never replace good cache',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'marketplace-cache-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      List<int> bytes = utf8.encode(jsonEncode([_entry]));
      var status = 200;
      final client = Dio()
        ..httpClientAdapter = _Adapter(
          () => ResponseBody.fromBytes(bytes, status),
        );
      final service = AgentSkillCatalogService(
        client: client,
        cacheDirectory: () async => dir,
      );
      addTearDown(service.dispose);
      expect(await service.readMarketplaceCache(), isNull);
      expect((await service.listMarketplace()).single.name, 'Dialogue');
      final cached = File('${dir.path}/skill_marketplace/catalog.json');
      final good = await cached.readAsString();
      bytes = utf8.encode('{bad json');
      await expectLater(service.listMarketplace(), throwsFormatException);
      expect(await cached.readAsString(), good);
      bytes = List.filled(AgentSkillCatalogService.maxCatalogBytes + 1, 32);
      await expectLater(service.listMarketplace(), throwsFormatException);
      expect(await cached.readAsString(), good);
      status = 429;
      bytes = utf8.encode('rate limited');
      await expectLater(
        service.listMarketplace(),
        throwsA(isA<DioException>()),
      );
      expect((await service.readMarketplaceCache())!.single.name, 'Dialogue');
    },
  );

  test(
    'cache is visible during refresh and survives failure; retries coalesce',
    () async {
      final service = _ControlledService();
      final container = ProviderContainer(
        overrides: [
          agentSkillCatalogServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      container.listen(marketplaceAgentSkillsProvider, (_, _) {});
      final notifier = container.read(marketplaceAgentSkillsProvider.notifier);
      await service.started.future;
      expect(
        container.read(marketplaceAgentSkillsProvider).skills!.single.name,
        'Dialogue',
      );
      expect(container.read(marketplaceAgentSkillsProvider).loading, isTrue);
      final pending = notifier.refresh();
      service.result.completeError(StateError('offline'));
      await pending;
      expect(
        container.read(marketplaceAgentSkillsProvider).error,
        isA<StateError>(),
      );
      expect(
        container.read(marketplaceAgentSkillsProvider).skills,
        hasLength(1),
      );
      service.result = Completer();
      final first = notifier.refresh();
      final second = notifier.refresh();
      expect(identical(first, second), isTrue);
      expect(service.calls, 2);
      service.result.complete([]);
      await first;
      expect(container.read(marketplaceAgentSkillsProvider).skills, isEmpty);
      expect(container.read(marketplaceAgentSkillsProvider).error, isNull);
    },
  );
}
