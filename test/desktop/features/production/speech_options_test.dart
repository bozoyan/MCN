// 职责: 验证预设与自定义音色写入同一保存字段，演绎说明与台词保持分离。
// 关联文件:
//   lib/desktop/features/production/speech_options.dart
//   lib/desktop/features/storyboard/edit_form.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/speech_options.dart';
import 'package:reveric/desktop/features/storyboard/edit_form.dart';
import 'package:reveric/shared/form/form.dart';
import 'package:reveric/shared/models/audio/speech.dart';
import '../../director/harness.dart';

class _Form extends HookWidget {
  const _Form(this.onSave);
  final void Function(String, String) onSave;
  @override
  Widget build(BuildContext context) {
    final form = useForm<ShotField>(
      listen: false,
      initialValues: {
        ShotField.audioVoice: 'Kore',
        ShotField.audioInstructions: '',
      },
    );
    return HookedForm(
      form: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProductionSpeechVoiceSelect(
            capability: speechModels['google/gemini-3.8-flash-tts']!,
            hasReference: false,
          ),
          const ProductionSpeechInstructions(),
          TextButton(
            onPressed: () => onSave(
              form.getValue<String>(ShotField.audioVoice)!,
              form.getValue<String>(ShotField.audioInstructions)!,
            ),
            child: const Text('Read values'),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(initializeDirectorTest);
  testWidgets(
    'preset choice and custom voice edits use the same persisted field',
    (tester) async {
      String? voice, instructions;
      await tester.pumpWidget(
        directorTestApp(
          // 工具栏里的音色菜单向上展开，表单贴底才放得下。
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 480,
              child: _Form((v, i) {
                voice = v;
                instructions = i;
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Firm female').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upbeat male'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read values'));
      expect(voice, 'Puck');
      await tester.tap(find.text('Upbeat male').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom voice ID…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'my-custom-voice');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('my-custom-voice'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Speak warmly');
      await tester.tap(find.text('Read values'));
      expect(voice, 'my-custom-voice');
      expect(instructions, 'Speak warmly');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
