// 职责: 验证朗读音色显示本地化名称，同时选择回调保留供应商 ID 与自定义值。
// 关联文件:
//   lib/desktop/features/narration/voice.dart
//   lib/shared/localization/audio_voice_localization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/audio.json
//   assets/translations/zh-CN/audio.json

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/narration/voice.dart';
import 'package:reveric/shared/localization/audio_voice_localization.dart';
import 'package:reveric/shared/models/audio/catalog.dart';
import '../../director/harness.dart';

void main() {
  setUpAll(initializeDirectorTest);
  setUp(() => rootBundle.clear());

  for (final (locale, selectedLabel, choiceLabel) in [
    (const Locale('zh', 'CN'), '活泼女声', '磁性男声'),
    (const Locale('en'), 'Lively female', 'Resonant male'),
  ]) {
    testWidgets(
      'voice labels in $locale preserve provider IDs',
      (tester) async {
        String? selected;
        await tester.pumpWidget(
          directorTestApp(
            Center(
              child: SizedBox(
                width: 400,
                child: NarrationVoiceSelect(
                  label: 'Voice',
                  value: 'longanhuan_v3.1',
                  voices: [
                    ...audioModelsCatalog['qwen-audio-3.1-tts-plus']!
                        .capabilities
                        .voices,
                    'opaque-preset',
                  ],
                  onChanged: (value) => selected = value,
                  allowNarrator: false,
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(selectedLabel), findsOneWidget);
        expect(find.text('longanhuan_v3.1'), findsNothing);
        await tester.tap(find.text(selectedLabel));
        await tester.pumpAndSettle();
        expect(find.text(choiceLabel), findsOneWidget);
        expect(find.text('xunanchuan_v3.1'), findsNothing);
        await tester.tap(find.text(choiceLabel));
        await tester.pumpAndSettle();
        expect(selected, 'xunanchuan_v3.1');
        await tester.tap(find.text(selectedLabel));
        await tester.pumpAndSettle();
        expect(find.text('opaque-preset'), findsNothing);
        await tester.tap(
          find.text(locale.languageCode == 'zh' ? '预设音色 5' : 'Preset voice 5'),
        );
        await tester.pumpAndSettle();
        expect(selected, 'opaque-preset');
        final context = tester.element(find.byType(NarrationVoiceSelect));
        expect(localizedAudioVoiceName(context, 'my-voice'), 'my-voice');
        expect(
          localizedAudioVoiceName(context, 'JBFqnCBsd6RMkjVDRZzb'),
          localizedAudioVoiceName(context, 'george'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
