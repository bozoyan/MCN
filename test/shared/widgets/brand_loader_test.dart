// 职责: 验证品牌加载动画的生命周期（入场→循环→完成后淡出）与关键帧排版。
// 关联文件:
//   lib/shared/widgets/brand_loader.dart
//   assets/logo/reveric_wordmark.png
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/brand_loader.dart';

Widget _wrap(Widget child, {bool dark = false, bool reduceMotion = false}) {
  final data = dark
      ? RevericThemeData.revericDark
      : RevericThemeData.reveric;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: RevericTheme(data: data, child: child!),
    ),
    home: RepaintBoundary(key: const ValueKey('capture'), child: child),
  );
}

void main() {
  testWidgets('done during intro waits for intro, then exits', (tester) async {
    var exited = 0;
    await tester.pumpWidget(
      _wrap(BrandLoader(done: true, onExited: () => exited++)),
    );
    // 入场 1.9s + 淡出 0.45s
    await tester.pump(const Duration(milliseconds: 2000));
    expect(exited, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(exited, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(exited, 1);
  });

  testWidgets('done after intro exits after fade', (tester) async {
    var exited = 0;
    Widget build(bool done) =>
        _wrap(BrandLoader(done: done, onExited: () => exited++));

    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(seconds: 5));
    expect(exited, 0);

    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(exited, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(exited, 1);
  });

  testWidgets('done during show delay exits without showing logo', (
    tester,
  ) async {
    var exited = 0;
    Widget build(bool done) => _wrap(
      BrandLoader(
        done: done,
        skipIntro: true,
        showDelay: const Duration(seconds: 1),
        onExited: () => exited++,
      ),
    );

    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(build(true));
    // logo 还没露面：不播淡出，下一帧直接结束
    await tester.pump();
    expect(exited, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(exited, 1);
  });

  testWidgets('show delay paints only background, then fades logo in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<List<int>> capture() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData();
        return data!.buffer.asUint8List().toList();
      });
      return bytes!;
    }

    await tester.pumpWidget(
      _wrap(
        const BrandLoader(skipIntro: true, showDelay: Duration(seconds: 1)),
      ),
    );
    final first = await capture();
    // 隐藏期内整屏都是背景色（RGBA 每 4 字节一组，全部等于第一个像素）
    final background = first.sublist(0, 4);
    for (var i = 0; i < first.length; i += 4) {
      expect(first.sublist(i, i + 4), background);
    }
    await tester.pump(const Duration(milliseconds: 900));
    expect(await capture(), first);
    // 隐藏期结束后淡入 logo
    await tester.pump(const Duration(milliseconds: 500));
    expect(await capture(), isNot(first));
  });

  testWidgets('reduce motion exits right after done', (tester) async {
    var exited = 0;
    Widget build(bool done) => _wrap(
      BrandLoader(done: done, onExited: () => exited++),
      reduceMotion: true,
    );

    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump();
    expect(exited, 1);
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('key frames $theme', (tester) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const BrandLoader(), dark: dark));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/logo/reveric_wordmark.png'),
          tester.element(find.byType(BrandLoader)),
        ),
      );

      // 描线中
      await tester.pump(const Duration(milliseconds: 600));
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('goldens/brand_loader_drawing_$theme.png'),
      );

      // 循环态（呼吸峰值附近）
      await tester.pump(const Duration(milliseconds: 2200));
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('goldens/brand_loader_loop_$theme.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
