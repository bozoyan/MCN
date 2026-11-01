// 职责: 验证 Android SAF 目录桥接结果解析与取消语义
// 关联文件:
//   lib/mobile/services/android_saf_directory_import.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/services/android_saf_directory_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('reveric/android_directory_import');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses copied directory result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickAndCopyDirectory');
          return <String, Object>{
            'path': '/data/user/0/ai.reveric/cache/import-1',
            'name': '资料',
            'fileCount': 2,
            'directoryCount': 1,
          };
        });

    final result = await pickAndCopyAndroidDirectory();

    expect(result, isNotNull);
    expect(result!.directoryPath, contains('/cache/import-1'));
    expect(result.directoryName, '资料');
    expect(result.fileCount, 2);
    expect(result.directoryCount, 1);
  });

  test('returns null when Android picker is cancelled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    expect(await pickAndCopyAndroidDirectory(), isNull);
  });

  test('writes exported files through the Android directory bridge', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickAndWriteFiles');
          final arguments = call.arguments! as Map<Object?, Object?>;
          final files = arguments['files']! as List<Object?>;
          expect(files.single, {
            'path': 'skill/references/guide.md',
            'content': '# guide',
          });
          return <String, Object>{'name': 'Downloads', 'fileCount': 1};
        });

    final result = await writeFilesToAndroidDirectory(
      files: const [
        AndroidSafExportFile(
          relativePath: 'skill/references/guide.md',
          content: '# guide',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.directoryName, 'Downloads');
    expect(result.fileCount, 1);
  });
}
