// 职责: 测试封面档案 — 模型返回解析、novel_states 落库与读取、孤儿 reading 复位与读稿超时。
// 关联文件:
//   lib/shared/services/ai/cover_brief_service.dart
//   lib/shared/models/cover_brief.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/cover_brief.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/cover_brief_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseCoverBriefResponse', () {
    test('解析裸 JSON', () {
      final draft = parseCoverBriefResponse(
        '{"category":"历史 · 群像","style":"水墨写意","palette":"墨与宣",'
        '"temperature":"冷灰为底",'
        '"figure":"以意象替代人物","era":"明末江南",'
        '"motifs":[{"text":"江面与渔火","from":"第 3 章 夜泊"}]}',
      );

      expect(draft, isNotNull);
      expect(draft!.category, '历史 · 群像');
      expect(draft.style, '水墨写意');
      expect(draft.palette, '墨与宣');
      expect(draft.motifs.single.text, '江面与渔火');
      expect(draft.motifs.single.from, '第 3 章 夜泊');
    });

    test('模型把 JSON 包在代码块和解释文字里也能取出来', () {
      final draft = parseCoverBriefResponse('''
好的，我读完了开头三章，判断如下：

```json
{"category":"都市 · 悬疑","style":"摄影写实","palette":"夜航","temperature":"夜色为底","figure":"单一主角","era":"当代",
 "motifs":[{"text":"雨夜霓虹","from":"第 1 章"}]}
```

如需调整请告诉我。
''');

      expect(draft, isNotNull);
      expect(draft!.category, '都市 · 悬疑');
      expect(draft.style, '摄影写实');
      expect(draft.palette, '夜航');
      expect(draft.motifs.single.text, '雨夜霓虹');
    });

    test('字符串里的花括号不会把对象提前截断', () {
      final draft = parseCoverBriefResponse(
        '{"category":"科幻","style":"","palette":"","temperature":"用 {brace} 做比喻","figure":"",'
        '"era":"","motifs":[]}',
      );

      expect(draft, isNotNull);
      expect(draft!.temperature, '用 {brace} 做比喻');
    });

    test('风格色调按正文自由表述原样收下，不限制在芯片预设里', () {
      final draft = parseCoverBriefResponse(
        '{"category":"玄幻","style":"青绿山水长卷","palette":"石青石绿为底",'
        '"temperature":"","figure":"","era":"","motifs":[]}',
      );

      expect(draft, isNotNull);
      expect(draft!.style, '青绿山水长卷');
      expect(draft.palette, '石青石绿为底');
      expect(draft.category, '玄幻');
    });

    test('没有出处的意象直接丢掉', () {
      final draft = parseCoverBriefResponse(
        '{"category":"武侠","style":"","palette":"","temperature":"","figure":"","era":"",'
        '"motifs":[{"text":"孤舟","from":"第 2 章"},{"from":"第 5 章"},{"text":""}]}',
      );

      expect(draft!.motifs, hasLength(1));
      expect(draft.motifs.single.text, '孤舟');
    });

    test('解不出 JSON 或全空时返回 null，不落一份假档案', () {
      expect(parseCoverBriefResponse('我不知道该怎么判断。'), isNull);
      expect(parseCoverBriefResponse('{"category":"","motifs":[]}'), isNull);
      expect(parseCoverBriefResponse('{"category": 未闭合'), isNull);
    });
  });

  group('CoverBrief 落库与读取', () {
    late NovelContentDatabase contentDb;

    setUp(() {
      contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    });

    tearDown(() async => contentDb.close());

    test('没读过时 load 返回 null，watch 也不认为在读', () async {
      final service = CoverBriefService(clientFactory: () async => null);

      expect(await service.load(contentDb), isNull);
      final state = await service.watch(contentDb).first;
      expect(state.brief, isNull);
      expect(state.reading, isFalse);
    });

    test('存进 novel_states 的档案能原样读回来', () async {
      final service = CoverBriefService(clientFactory: () async => null);
      final brief = CoverBrief(
        category: '历史 · 群像',
        style: '水墨写意',
        palette: '墨与宣',
        temperature: '冷灰为底',
        figure: '以意象替代人物',
        era: '明末江南',
        motifs: const [CoverBriefMotif(text: '江面与渔火', from: '第 3 章 夜泊')],
        readAt: DateTime(2026, 8, 11, 14, 20),
        sources: [
          CoverBriefSource(chapterId: 'c1', updatedAt: DateTime(2026, 8, 1)),
        ],
        chapterCount: 42,
        wordCount: 184000,
      );
      await contentDb.novelStateDao.upsert(
        key: novelStateKeyCoverBrief,
        status: novelStateStatusIdle,
        data: jsonEncode(brief.toJson()),
      );

      final loaded = await service.load(contentDb);

      expect(loaded, isNotNull);
      expect(loaded!.category, '历史 · 群像');
      expect(loaded.style, '水墨写意');
      expect(loaded.palette, '墨与宣');
      expect(loaded.readAt, DateTime(2026, 8, 11, 14, 20));
      expect(loaded.sources.single.chapterId, 'c1');
      expect(loaded.chapterCount, 42);
    });

    test('旧档案缺风格色调字段时按空串读回，不炸', () async {
      final service = CoverBriefService(clientFactory: () async => null);
      await contentDb.novelStateDao.upsert(
        key: novelStateKeyCoverBrief,
        status: novelStateStatusIdle,
        data: jsonEncode({
          'category': '旧档案',
          'temperature': '',
          'figure': '',
          'era': '',
          'motifs': [],
          'read_at': '2026-08-01T00:00:00.000',
          'sources': [],
          'chapter_count': 10,
          'word_count': 20000,
        }),
      );

      final loaded = await service.load(contentDb);

      expect(loaded, isNotNull);
      expect(loaded!.style, isEmpty);
      expect(loaded.palette, isEmpty);
      expect(loaded.category, '旧档案');
    });

    test('读取中状态能被 watch 观察到，且旧档案不被清空', () async {
      await _insertChapter(contentDb);
      final brief = CoverBrief(
        category: '旧档案',
        style: '',
        palette: '',
        temperature: '',
        figure: '',
        era: '',
        motifs: const [],
        readAt: DateTime(2026, 8, 1),
        sources: const [],
        chapterCount: 10,
        wordCount: 20000,
      );
      await contentDb.novelStateDao.upsert(
        key: novelStateKeyCoverBrief,
        status: novelStateStatusIdle,
        data: jsonEncode(brief.toJson()),
      );
      final hang = Completer<AiClient?>();
      final readingService = CoverBriefService(
        clientFactory: () => hang.future,
      );
      final readFuture = readingService.read(
        contentDb: contentDb,
        novelTitle: '南渡记',
        novelDescription: '',
      );
      await contentDb.novelStateDao
          .watch(novelStateKeyCoverBrief)
          .firstWhere((row) => row?.status == coverBriefStatusReading);

      final state = await readingService.watch(contentDb).first;

      expect(state.reading, isTrue);
      expect(state.brief?.category, '旧档案');
      hang.complete(null);
      expect(await readFuture, isNull);
    });

    test('库里是坏 JSON 时降级成「没读过」，不抛异常', () async {
      final service = CoverBriefService(clientFactory: () async => null);
      await contentDb.novelStateDao.upsert(
        key: novelStateKeyCoverBrief,
        status: novelStateStatusIdle,
        data: 'not json at all',
      );

      expect(await service.load(contentDb), isNull);
    });

    test('没有正文时不读稿、不写库 —— 读稿失败不该挡住出图', () async {
      final service = CoverBriefService(clientFactory: () async => null);

      final result = await service.read(
        contentDb: contentDb,
        novelTitle: '南渡记',
        novelDescription: '',
      );

      expect(result, isNull);
      expect(
        await contentDb.novelStateDao.get(novelStateKeyCoverBrief),
        isNull,
        reason: '连状态行都不该建，界面仍显示「还没读过」',
      );
    });

    test('进程里没有在读时，watch 把遗留的 reading 复位成 idle', () async {
      final service = CoverBriefService(clientFactory: () async => null);
      await contentDb.novelStateDao.upsert(
        key: novelStateKeyCoverBrief,
        status: coverBriefStatusReading,
      );

      final state = await service.watch(contentDb).first;

      expect(state.reading, isFalse);
      expect(state.brief, isNull);
      expect(
        (await contentDb.novelStateDao.get(novelStateKeyCoverBrief))?.status,
        novelStateStatusIdle,
      );
    });

    test('读稿超时后把 reading 复位成 idle，不永久转圈', () async {
      await _insertChapter(contentDb);
      final hang = Completer<AiClient?>();
      final service = CoverBriefService(
        clientFactory: () => hang.future,
        timeout: const Duration(milliseconds: 30),
      );

      final result = await service.read(
        contentDb: contentDb,
        novelTitle: '南渡记',
        novelDescription: '',
      );

      expect(result, isNull);
      expect(
        (await contentDb.novelStateDao.get(novelStateKeyCoverBrief))?.status,
        novelStateStatusIdle,
      );
    });
  });
}

Future<void> _insertChapter(NovelContentDatabase contentDb) async {
  final now = DateTime.now();
  await contentDb.chapterDao.insert(
    ChaptersCompanion.insert(
      id: 'c1',
      type: nodeTypeChapter,
      siblingOrder: 1,
      title: const Value('夜泊'),
      content: const Value('江面与渔火。'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}
