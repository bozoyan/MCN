// 职责: 全局大纲对比板黄金图（加载真实字体），人工目检真实文字下的对齐与可读性（非 CI 断言）。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_global_view.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/outline_global_view.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/outline.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    // display/heading 硬编码 'Georgia'（系统字体，测试环境缺失）→ 用中文字体代打，好让标题也可见。
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
  });

  testWidgets('golden: aligned board with real fonts', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _wrap(AllOutlinesArchitectureView(outlines: _sampleOutlines())),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AllOutlinesArchitectureView),
      matchesGoldenFile('goldens/outline_global_view.png'),
    );
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(
            fontFamily: 'LXGWWenKai',
          ),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

List<OutlineDraft> _sampleOutlines() {
  const mainTitles = [
    '穿越降临',
    '找到盟友',
    '首个成果',
    '破圈爆发',
    '遭遇暗算',
    '绝地反击',
    '甜蜜暗涌',
    '家世风波',
    '产品迭代',
    '正面交锋',
    '挖角风波',
    '苏瑶身世',
    'A轮融资',
    '蝴蝶振翅',
    '竞品围剿',
    '暗流涌动',
    '巨头入场',
    '技术封锁',
  ];
  const mainCounts = [5, 5, 5, 5, 5, 5, 5, 5, 12, 5, 5, 20, 5, 5, 5, 15, 5, 5];
  const romanceTitles = [
    '初遇',
    '误会渐生',
    '暗生情愫',
    '第一次心动',
    '表白',
    '热恋',
    '身世危机',
    '短暂分离',
    '重逢',
    '并肩',
    '坦白心迹',
  ];
  const romanceCounts = [2, 1, 3, 2, 1, 2, 3, 1, 2, 1, 2];
  return [
    _outline(title: '主线', titles: mainTitles, counts: mainCounts),
    _outline(title: '林默&苏瑶感情线', titles: romanceTitles, counts: romanceCounts),
  ];
}

OutlineDraft _outline({
  required String title,
  required List<String> titles,
  required List<int> counts,
}) {
  final now = DateTime(2026);
  return OutlineDraft(
    documentId: title,
    title: title,
    beats: [
      for (var i = 0; i < titles.length; i++)
        OutlineBeatDraft(
          id: '${title}_$i',
          title: titles[i],
          content:
              '${titles[i]}：本节拍的剧情概要，用于验证卡片描述区的渲染、'
              '按高度分级降级，以及长节拍卡片用描述填充留白的效果。',
          chapterCount: counts[i],
          sortOrder: i,
        ),
    ],
    createdAt: now,
    updatedAt: now,
    deletedAt: now,
  );
}
