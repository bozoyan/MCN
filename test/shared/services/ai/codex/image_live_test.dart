// 职责: 显式启用时验证本机 Codex 账号的真实生图与参考图编辑。
// 关联文件:
//   lib/shared/services/ai/image.dart
//   lib/shared/agent/client/codex_client.dart
//   lib/shared/models/ai_provider.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:reveric/shared/agent/client/codex_client.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/services/ai/image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local Codex generates an image and edits the result',
    () async {
      HttpOverrides.global = null;
      final support = await Directory.systemTemp.createTemp(
        'reveric-codex-image-live-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(channel, (_) async => support.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final catalogClient = http.Client();
      final List<String> models;
      try {
        models = await CodexClient.fetchModels(client: catalogClient);
      } finally {
        catalogClient.close();
      }
      debugPrint(
        'Codex catalog: ${models.length} models; Luna available: ${models.contains('gpt-6-luna')}',
      );
      final provider = aiProviderBuiltinById('openai')!.copyWith(
        id: 'codex-image-smoke',
        name: 'Codex',
        type: 'codex',
        apiKey: '',
        models: models,
        imageModels: ['gpt-image-2'],
      );
      final service = AiImageGenerationService(provider, model: 'gpt-image-2');
      final generated = await service.generateImage(
        'Generate an image of a single solid blue circle centered on a plain white background. No text.',
        size: '1024x1024',
        quality: 'low',
      );
      final firstBytes = await File(generated.localFilePath!).readAsBytes();
      expect(img.decodeImage(firstBytes), isNotNull);
      debugPrint(
        'Generated ${firstBytes.length} bytes: ${generated.localFilePath}',
      );
      final edited = await service.editImage(
        'Change the blue circle to red. Keep its position and the white background. No text.',
        imageData: generated.localFilePath!,
        size: '1024x1024',
        quality: 'low',
      );
      final editedBytes = await File(edited.localFilePath!).readAsBytes();
      expect(img.decodeImage(editedBytes), isNotNull);
      debugPrint('Edited ${editedBytes.length} bytes: ${edited.localFilePath}');
    },
    skip: Platform.environment['REVERIC_CODEX_IMAGE_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
