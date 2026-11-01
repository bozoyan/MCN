// 职责: 验证生成图片的存储路径能够显示，并以已有资产 ID 应用为头像或照片。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/tools/character_image_tool_card.dart
//   lib/shared/services/image_library_service.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/image_library_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_view.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';
import 'package:reveric/shared/widgets/ai/tools/character_image_tool_card.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const relative = 'file_workspaces/work/images/generated.png';
  late Directory root;
  late File source;
  late AppDatabase database;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() async {
    rootBundle.clear();
    root = await Directory.systemTemp.createTemp('generated-image-paths-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    await RevericPaths.initialize();
    source = File(p.join(root.path, relative));
    await source.parent.create(recursive: true);
    await source.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    database = AppDatabase.forTest(NativeDatabase.memory());
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      '$platform renders stored image paths and applies registered assets',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        expect(File(relative).existsSync(), isFalse);
        // Start file decoding outside FakeAsync before Image can cache its future.
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.runAsync(
          () => precacheImage(
            FileImage(source),
            tester.element(find.byType(SizedBox).first),
          ).timeout(const Duration(seconds: 10)),
        );
        final library = buildImageLibraryService(database);
        for (final (stored, tool, expectedCharacterId, expectedItemId, purpose)
            in [
              (
                relative,
                'GenerateAvatar',
                'character',
                null,
                AssetPurpose.avatar,
              ),
              (
                source.path,
                'GeneratePhoto',
                'character',
                null,
                AssetPurpose.photo,
              ),
              (relative, 'GeneratePhoto', null, 'item', AssetPurpose.photo),
            ]) {
          final registered = (await tester.runAsync(
            () => library.importFile(
              source.path,
              novelId: 'work',
              purpose: purpose,
            ),
          ))!;
          final assetCount = (await tester.runAsync(
            () => database.select(database.assets).get(),
          ))!.length;
          late Completer<AssetRow> applied;
          String? callbackAssetId;
          Future<void> apply(String assetId) async {
            callbackAssetId = assetId;
            try {
              applied.complete(
                (await database.imageAssetDao.getAsset(assetId))!,
              );
            } catch (error, stack) {
              applied.completeError(error, stack);
            }
          }

          final block = AiImageBlock(
            id: 'image',
            prompt: 'portrait',
            toolName: tool,
            localFilePath: stored,
            assetId: registered.id,
            characterId: expectedCharacterId,
            itemId: expectedItemId,
            status: AiImageStatus.success,
          );
          await tester.pumpWidget(
            _wrap(
              ChatMessageView(
                message: UIMessage(
                  id: 'message',
                  role: AiMessageRole.assistant,
                  type: AiMessageType.text,
                  content: '',
                  blocks: [block],
                  isStreaming: false,
                  isStreamingTail: false,
                  sourceIds: const ['message'],
                ),
                activeSessionId: null,
                onSetAsAvatar: (path, id) async {
                  expect(id, expectedCharacterId);
                  await apply(path);
                },
                onAddPhoto: (path, {characterId, itemId}) async {
                  expect(characterId, expectedCharacterId);
                  expect(itemId, expectedItemId);
                  await apply(path);
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.byType(AiCharacterImageToolCard);
          final images = tester
              .widgetList<Image>(
                find.descendant(of: card, matching: find.byType(Image)),
              )
              .where((image) => image.image is FileImage)
              .toList();
          expect(images, hasLength(1));
          expect((images.single.image as FileImage).file.path, source.path);
          await tester.pump();
          expect(
            tester
                .widgetList<RawImage>(
                  find.descendant(of: card, matching: find.byType(RawImage)),
                )
                .any((image) => image.image != null),
            isTrue,
          );
          final action = find.descendant(
            of: card,
            matching: find.byType(OutlinedButton),
          );
          expect(action, findsOneWidget);
          final asset = await tester.runAsync(() async {
            applied = Completer<AssetRow>();
            await tester.tap(action);
            return applied.future.timeout(const Duration(seconds: 10));
          });
          await tester.pumpAndSettle();
          expect(callbackAssetId, registered.id);
          expect(asset!.id, registered.id);
          expect(
            (await tester.runAsync(
              () => database.select(database.assets).get(),
            ))!.length,
            assetCount,
          );
          expect(asset.novelId, 'work');
          expect(block.localFilePath, stored);
          expect(tester.takeException(), isNull);
        }
        for (final missingPath in [
          'file_workspaces/work/images/missing.png',
          '/old-container/$relative',
        ]) {
          await tester.pumpWidget(
            _wrap(
              ChatMessageView(
                message: UIMessage(
                  id: 'missing',
                  role: AiMessageRole.assistant,
                  type: AiMessageType.text,
                  content: '',
                  blocks: [
                    AiImageBlock(
                      id: 'image',
                      prompt: 'missing',
                      toolName: 'GenerateAvatar',
                      localFilePath: missingPath,
                      characterId: 'character',
                      status: AiImageStatus.success,
                    ),
                  ],
                  isStreaming: false,
                  isStreamingTail: false,
                  sourceIds: ['missing'],
                ),
                activeSessionId: null,
                onSetAsAvatar: (_, _) async =>
                    fail('Missing image must not be applied'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(OutlinedButton), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    aiAgentAvatarPathProvider.overrideWithValue(''),
    isImageGenerationConfiguredProvider.overrideWithValue(true),
  ],
  child: EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData(),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: Scaffold(
            body: TickerMode(
              enabled: false,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  ),
);
