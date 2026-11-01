// 职责: 测试 AI 工具枚举 alias 归一化与容错
// 关联文件:
//   lib/shared/services/ai/tools_enum_validation.dart
//   lib/shared/services/ai/tools.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/maps_service.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('AI enum alias normalization', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late LocationsService locationsService;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      locationsService = LocationsService(db);
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        createLocationCallback:
            ({
              required String name,
              String? description,
              String? type,
              String? parentId,
            }) {
              return locationsService.createLocation(
                name: name,
                description: description ?? '',
                type: type == null || type.isEmpty ? locationTypeGeneric : type,
                parentId: parentId,
              );
            },
      )..registerAllTools();
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    test('Create character accepts Chinese role and gender aliases', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'characters',
          'fields': {'name': '林默', 'role': '主角', 'gender': '男'},
        },
      );

      expect(result['created'], isTrue);
      final character = await contentService.getCharacterProfileById(
        result['id'] as String,
      );
      expect(character?.role, characterRoleProtagonist);
      expect(character?.gender, characterGenderMale);
    });

    test('Create character accepts main as protagonist role alias', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'characters',
          'fields': {'name': 'Alice', 'role': 'main'},
        },
      );

      expect(result['created'], isTrue);
      final character = await contentService.getCharacterProfileById(
        result['id'] as String,
      );
      expect(character?.role, characterRoleProtagonist);
    });

    test('Create foreshadowing accepts Chinese status aliases', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'foreshadowing',
          'fields': {'title': '穿越的秘密', 'status': '已铺垫'},
        },
      );

      expect(result['created'], isTrue);
      final entry = await contentService.getForeshadowingById(
        result['id'] as String,
      );
      expect(entry?.status, foreshadowingStatusPlanted);
    });

    test(
      'Create and Write normalize setup foreshadowing status to planted',
      () async {
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'foreshadowing',
            'fields': {'title': '已铺垫线索', 'status': 'setup'},
          },
        );
        expect(created['ok'], isTrue, reason: '$created');
        final id = created['id'] as String;
        expect(
          (await contentService.getForeshadowingById(id))?.status,
          foreshadowingStatusPlanted,
        );
        for (final status in ['pending', 'setup']) {
          final written = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'foreshadowing/$id',
              'fields': {'status': status},
            },
          );
          expect(written['ok'], isTrue, reason: '$written');
          expect(
            (await contentService.getForeshadowingById(id))?.status,
            status == 'setup'
                ? foreshadowingStatusPlanted
                : foreshadowingStatusPending,
          );
        }
      },
    );

    test('Create outline accepts active as in-progress status alias', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'outlines',
          'fields': {'title': '主线', 'status': 'active'},
        },
      );

      expect(result['created'], isTrue);
    });

    test(
      'Create outline accepts Chinese 活跃 as in-progress status alias',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines',
            'fields': {'title': '支线', 'status': '活跃'},
          },
        );

        expect(result['created'], isTrue);
        final outline = await contentService.outlineService.getByTitle('支线');
        expect(outline?.status, 'in_progress');
      },
    );

    test('Create lore folder accepts Chinese type alias', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'lore/设定资料',
          'fields': {'type': '文件夹'},
        },
      );

      expect(result['created'], isTrue);
      expect(result['is_folder'], isTrue);
    });

    test('Create location accepts Chinese type alias', () async {
      final world = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'locations',
          'fields': {'name': '地球', 'type': '世界'},
        },
      );
      expect(world['created'], isTrue);

      final city = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'locations',
          'fields': {'name': '上海', 'type': '城市', 'parent_id': world['id']},
        },
      );

      expect(city['created'], isTrue);
      final location = await contentService.locationsService.getLocationById(
        city['id'] as String,
      );
      expect(location?.type, locationTypeCity);

      final area = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'locations',
          'fields': {'name': '浦东', 'type': 'area', 'parent_id': world['id']},
        },
      );

      expect(area['created'], isTrue);
      final areaLocation = await contentService.locationsService
          .getLocationById(area['id'] as String);
      expect(areaLocation?.type, locationTypeRegion);
    });
  });
}
