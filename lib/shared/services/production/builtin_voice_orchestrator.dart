// 职责: 校验包内音色并通过现有媒体导入流程生成当前作品可引用的音频资产。
// 关联文件:
//   lib/shared/models/production/builtin_voices.dart
//   lib/shared/services/production/library_service.dart
//   lib/shared/services/production/import_orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import '../../database/app_database.dart';
import '../../logger/app_logger.dart';
import '../../models/asset_purpose.dart';
import '../../models/production/builtin_voices.dart';
import 'ffmpeg_runner.dart';
import 'library_service.dart';

final _log = AppLogger.forModule('BuiltinVoice');

class BuiltinVoiceOrchestrator {
  Future<AssetRow> run({
    required MediaLibraryService library,
    required String novelId,
    required BuiltinVoice voice,
    required String name,
    AssetBundle? bundle,
  }) async {
    if (!productionBuiltinVoices.contains(voice)) {
      throw ArgumentError.value(voice.id, 'voice', 'Unknown built-in voice');
    }
    Directory? temporary;
    try {
      _log.info('materialize started id=${voice.id}');
      final data = await (bundle ?? rootBundle).load(voice.bundlePath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (crypto.sha256.convert(bytes).toString() != voice.sha256) {
        throw const FormatException('Built-in voice integrity check failed');
      }
      temporary = await Directory.systemTemp.createTemp(
        'reveric_builtin_voice_',
      );
      final file = await File(
        '${temporary.path}/${voice.id}.wav',
      ).writeAsBytes(bytes, flush: true);
      final asset = await library.importFile(
        file,
        name: '$name.wav',
        novelId: novelId,
        purpose: AssetPurpose.production_upload,
        cancellation: MediaCancellation(),
        source: 'bundled',
      );
      _log.info('materialize completed id=${voice.id} asset=${asset.id}');
      return asset;
    } catch (error, stack) {
      _log.error(
        'materialize failed id=${voice.id}',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    } finally {
      if (temporary != null) {
        await temporary.delete(recursive: true);
      }
    }
  }
}
