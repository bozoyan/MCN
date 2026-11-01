// 职责: 画布节点卡片黄金图 — 用真实字体渲染引用型/便签型节点，人工目检截断与对齐
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_node_widget.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
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
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
  });

  testWidgets('golden: reference and sticky cards with real fonts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模拟截图中的第一行：章节引用 + 4 个 beat 便签
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reference(
                  title: '穿越之始',
                  refType: entityTypeChapter,
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: 'Beat 0 穿越降临',
                  content: '【穿越降临】第1-5章\n林默穿越回2015，确认时间锚点',
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: 'Beat 1 找到盟友',
                  content: '【找到盟友】第6-10章\n遇见苏瑶，用未来AI理念打动她',
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: 'Beat 2 首个成果',
                  content: '【首个成果】第11-15章\n原型完成，苏瑶关键算法突破',
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: 'Beat 3 破圈爆发',
                  content: '【破圈爆发】第16-20章',
                ),
              ],
            ),
            const SizedBox(height: 40),
            // 模拟截图中的第二行：感情线便签
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sticky(
                  title: '磨合期暗生情愫',
                  content: '第8-10章左右\n苏瑶发现林默长期熬夜背后的秘密',
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: '好感升级→确认交往',
                  content: '第11-14章\n竞品挖角苏瑶被拒，团队凝聚力提升',
                ),
              ],
            ),
            const SizedBox(height: 40),
            // 模拟截图中的第三行：伏笔引用
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reference(
                  title: '穿越的秘密',
                  refType: entityTypeForeshadowing,
                ),
                const SizedBox(width: 24),
                _reference(
                  title: "黑客'鸭舌帽'的攻击",
                  refType: entityTypeForeshadowing,
                ),
              ],
            ),
            const SizedBox(height: 40),
            // 第四行：选中态(3px 强调色外环) 与失效态(虚线 + 删除线)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reference(
                  title: '选中的章节',
                  refType: entityTypeChapter,
                  isSelected: true,
                ),
                const SizedBox(width: 24),
                _reference(
                  title: '已删除的资源',
                  refType: entityTypeCharacter,
                  isInvalid: true,
                ),
                const SizedBox(width: 24),
                _sticky(
                  title: '选中的便签',
                  content: '第21-25章\n选中态只加描边与外环，不改纸色',
                  isSelected: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/canvas_node_cards.png'),
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
          debugShowCheckedModeBanner: false,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(
            fontFamily: 'LXGWWenKai',
          ),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(
              backgroundColor: RevericThemeData.reveric.colors.canvas,
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: child,
              ),
            ),
          ),
        );
      },
    ),
  );
}

CanvasNode _canvasNode({
  required String type,
  String? refType,
  required String title,
  required String content,
  double? width,
  double? height,
}) {
  return CanvasNode(
    id: 'node_${title.hashCode}',
    canvasId: 'canvas_golden',
    type: type,
    refType: refType,
    refId: refType != null ? 'ref_${title.hashCode}' : null,
    title: title,
    content: content,
    x: 0,
    y: 0,
    width: width,
    height: height,
    zIndex: 0,
    sortOrder: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deletedAt: notDeletedSentinel,
  );
}

Widget _reference({
  required String title,
  required String refType,
  bool isSelected = false,
  bool isInvalid = false,
}) {
  return SizedBox(
    width: canvasReferenceNodeSize.width,
    height: canvasReferenceNodeSize.height,
    child: CanvasReferenceNodeCard(
      node: _canvasNode(
        type: canvasNodeTypeReference,
        refType: refType,
        title: title,
        content: '',
      ),
      isInvalid: isInvalid,
      isSelected: isSelected,
    ),
  );
}

Widget _sticky({
  required String title,
  required String content,
  bool isSelected = false,
}) {
  return SizedBox(
    width: canvasStickyDefaultWidth,
    height: canvasStickyDefaultHeight,
    child: CanvasStickyNodeCard(
      node: _canvasNode(
        type: canvasNodeTypeSticky,
        title: title,
        content: content,
      ),
      isSelected: isSelected,
    ),
  );
}
