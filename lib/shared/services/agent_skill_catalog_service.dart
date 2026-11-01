// 职责: 加载本地官方技能与远端广场目录，缓存最近一次有效广场列表。
// 关联文件:
//   lib/shared/services/bundled_official_skills.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/models/marketplace_agent_skill.dart
//   lib/shared/app_config.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../logger/app_logger.dart';
import '../models/marketplace_agent_skill.dart';

import 'bundled_official_skills.dart';
import '../models/official_agent_skill.dart';

export '../models/official_agent_skill.dart';

final _log = AppLogger.forModule('AgentSkillCatalog');

/// AgentSkillCatalog 域服务。单例,由 Provider 管理生命周期。
///
class AgentSkillCatalogService {
  AgentSkillCatalogService({
    this._officialSkills = const BundledOfficialSkillsLoader(),
    this._assetBundle,
    this._client,
    this._createClient,
    Future<Directory> Function()? cacheDirectory,
  }) : _cacheDirectory = cacheDirectory ?? getApplicationSupportDirectory;

  final BundledOfficialSkillsLoader _officialSkills;
  final AssetBundle? _assetBundle;
  final Dio? _client;
  final Future<Dio> Function()? _createClient;
  final Future<Directory> Function() _cacheDirectory;

  static const maxCatalogBytes = 2 * 1024 * 1024;

  void dispose() => _client?.close(force: true);

  Future<File> _cacheFile() async =>
      File('${(await _cacheDirectory()).path}/skill_marketplace/catalog.json');

  Future<List<MarketplaceAgentSkill>?> readMarketplaceCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        return null;
      }
      if (await file.length() > maxCatalogBytes) {
        throw const FormatException('Cached skill catalog exceeds size limit');
      }
      return MarketplaceAgentSkill.parseCatalog(
        jsonDecode(await file.readAsString()),
      );
    } catch (error, stackTrace) {
      _log.error(
        'Cannot read skill catalog cache',
        error: error,
        stackTrace: stackTrace,
      );
      // 目录缓存可重建；失败后仍向网络请求，网络失败由列表明确展示。
      return null;
    }
  }

  Future<List<MarketplaceAgentSkill>> listMarketplace() async {
    Dio? client;
    final token = CancelToken();
    final bytes = BytesBuilder(copy: false);
    try {
      final factory = _createClient;
      client =
          _client ??
          (factory != null
              ? await factory()
              : throw StateError(
                  'Marketplace HTTP client factory is required',
                ));
      final response = await client
          .get<ResponseBody>(
            revericSkillsCatalogUrl,
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              token.cancel('Catalog connection timed out');
              throw const FormatException('Catalog connection timed out');
            },
          );
      await for (final chunk in response.data!.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > maxCatalogBytes) {
          throw const FormatException('Skill catalog exceeds size limit');
        }
        bytes.add(chunk);
      }
      final raw = bytes.takeBytes();
      final list = MarketplaceAgentSkill.parseCatalog(
        jsonDecode(utf8.decode(raw)),
      );
      try {
        final file = await _cacheFile();
        await file.parent.create(recursive: true);
        final temporary = File(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temporary.writeAsBytes(raw, flush: true);
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) {
            await temporary.delete();
          }
        }
      } catch (error, stackTrace) {
        _log.error(
          'Cannot save skill catalog cache',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return list;
    } catch (error, stackTrace) {
      _log.error(
        'Load marketplace failed url=$revericSkillsCatalogUrl',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      token.cancel('Catalog request finished');
      if (_client == null) {
        client?.close(force: true);
      }
    }
  }

  AssetBundle get _bundle => _assetBundle ?? rootBundle;

  /// 全量官方目录。读本地打包技能，不打网、不分页。
  ///
  /// 目录固定十余条且完全在本地，category/tag 过滤由
  /// `OfficialAgentSkillsNotifier` 在内存里做，这里不再重复一套过滤真源。
  Future<OfficialAgentSkillCatalog> listOfficial() =>
      _officialSkills.list(_bundle);

  /// 官方 AgentSkill 详情。`listingId` 即技能 name。
  Future<OfficialAgentSkill> getOfficial({required String listingId}) =>
      _officialSkills.get(_bundle, listingId);
}
