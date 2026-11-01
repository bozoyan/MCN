// 职责: 用真实字体审核共享按钮在桌面、窄屏、明暗主题及加载状态下的视觉一致性。
// 关联文件:
//   lib/shared/components/reveric_button.dart
//   lib/shared/theme/reveric_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/theme/theme.dart';

import '../../helpers/button_golden_theme.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('ButtonTest');
    loader.addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
    await loader.load();
  });
  for (final mobile in [false, true]) {
    for (final dark in [false, true]) {
      final name =
          '${mobile ? 'mobile' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets('button states $name', (tester) async {
        tester.view.physicalSize = Size(
          mobile ? 375 : 1000,
          mobile ? 1000 : 900,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = dark
            ? RevericThemeData.revericDark
            : RevericThemeData.reveric;
        await tester.pumpWidget(
          MaterialApp(
            theme: withGoldenButtonFont(
              data
                  .toThemeData(fontFamily: 'ButtonTest')
                  .copyWith(
                    platform: mobile
                        ? TargetPlatform.android
                        : TargetPlatform.macOS,
                  ),
            ),
            home: RevericTheme(
              data: data,
              child: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('buttons'),
                  child: ColoredBox(
                    color: data.colors.canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '标准按钮 / Standard',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.primary(
                                label: '保存',
                                icon: RevericIcons.check,
                                onPressed: () {},
                              ),
                              RevericButton.secondary(
                                label: '检查更新',
                                icon: RevericIcons.arrows_clockwise,
                                onPressed: () {},
                              ),
                              RevericButton.text(label: '取消', onPressed: () {}),
                              RevericButton.danger(
                                label: '删除',
                                icon: RevericIcons.delete,
                                onPressed: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '主操作 / Prominent',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.primary(
                                label: '继续写作',
                                icon: RevericIcons.pencil_simple,
                                size: RevericButtonSize.prominent,
                                onPressed: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '紧凑按钮 / Compact',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.primary(
                                label: '继续',
                                size: RevericButtonSize.compact,
                                onPressed: () {},
                              ),
                              RevericButton.secondary(
                                label: 'Select all',
                                size: RevericButtonSize.compact,
                                onPressed: () {},
                              ),
                              RevericButton.text(
                                label: '清空',
                                size: RevericButtonSize.compact,
                                onPressed: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '加载 / Loading',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.primary(
                                label: '保存',
                                icon: RevericIcons.check,
                                loading: true,
                                onPressed: () {},
                              ),
                              RevericButton.secondary(
                                label: '检查更新',
                                icon: RevericIcons.arrows_clockwise,
                                loading: true,
                                onPressed: () {},
                              ),
                              RevericButton.text(
                                label: 'Continue',
                                loading: true,
                                onPressed: () {},
                              ),
                              RevericButton.danger(
                                label: '删除',
                                icon: RevericIcons.delete,
                                loading: true,
                                onPressed: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '不可用 / Disabled',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.primary(
                                label: '保存',
                                icon: RevericIcons.check,
                                onPressed: null,
                              ),
                              RevericButton.secondary(
                                label: '检查更新',
                                icon: RevericIcons.arrows_clockwise,
                                onPressed: null,
                              ),
                              RevericButton.text(label: '取消', onPressed: null),
                              RevericButton.danger(
                                label: '删除',
                                icon: RevericIcons.delete,
                                onPressed: null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '窄屏换行 / Long labels',
                            style: data.typography.uiSemibold,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              RevericButton.secondary(
                                label: '查看大纲',
                                icon: RevericIcons.list_alt_outlined,
                                onPressed: () {},
                              ),
                              RevericButton.secondary(
                                label: 'Browse worldbuilding settings',
                                icon: RevericIcons.public_outlined,
                                onPressed: () {},
                              ),
                              RevericButton.secondary(
                                label: '智能体配置',
                                icon: RevericIcons.auto_awesome_outlined,
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('buttons')),
          matchesGoldenFile('goldens/buttons_$name.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
