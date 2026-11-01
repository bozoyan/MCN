// 职责: 验证表单字段离屏回收后恢复编辑值，并保留清空、重置和切换表单语义。
// 关联文件:
//   lib/shared/form/hooked_text_form_field.dart
//   lib/third/form/src/widget/hooked_form_field.dart
//   lib/third/form/src/models/form_field_controller.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/form/form.dart';
import 'package:reveric/shared/theme/theme.dart';

enum _Field implements FieldSchema {
  title,
  category;

  @override
  List<Validator<dynamic>>? get validators => null;
}

Widget _harness(
  FormFieldsController<_Field> form,
  ScrollController scroll, {
  TextEditingController? textController,
}) {
  return MaterialApp(
    theme: RevericThemeData.reveric.toThemeData(),
    home: RevericTheme(
      data: RevericThemeData.reveric,
      child: Scaffold(
        body: HookedForm<_Field>(
          form: form,
          child: ListView(
            controller: scroll,
            children: [
              HookedTextFormField<_Field>(
                fieldHook: _Field.title,
                controller: textController,
                initialValue: textController == null ? 'Title baseline' : null,
              ),
              HookedFormField<_Field, String>(
                fieldHook: _Field.category,
                initialValue: 'Category baseline',
                builder: (value, onChanged, error) => Text(value ?? 'none'),
              ),
              const SizedBox(height: 1800),
              const Text('Bottom'),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _scrollAway(WidgetTester tester, ScrollController scroll) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  scroll.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'external controller retains its original reset baseline after remount',
    (tester) async {
      final form = FormFieldsController<_Field>(GlobalKey<FormState>());
      final scroll = ScrollController();
      final text = TextEditingController(text: 'External baseline');
      addTearDown(form.dispose);
      addTearDown(scroll.dispose);
      addTearDown(text.dispose);
      await tester.pumpWidget(_harness(form, scroll, textController: text));
      await tester.enterText(find.byType(TextField), 'Edited external');
      await _scrollAway(tester, scroll);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(text.text, 'Edited external');
      expect(form.hasChanged, isTrue);
      form.reset();
      await tester.pumpAndSettle();
      expect(text.text, 'External baseline');
      expect(form.hasChanged, isFalse);
    },
  );

  testWidgets('swapping external controller adopts the new reset baseline', (
    tester,
  ) async {
    final form = FormFieldsController<_Field>(GlobalKey<FormState>());
    final scroll = ScrollController();
    final first = TextEditingController(text: 'First baseline');
    final second = TextEditingController(text: 'Second baseline');
    addTearDown(form.dispose);
    addTearDown(scroll.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(_harness(form, scroll, textController: first));
    await tester.pumpWidget(_harness(form, scroll, textController: second));
    expect(form.hasChanged, isFalse);
    await tester.enterText(find.byType(TextField), 'Edited second');
    expect(form.hasChanged, isTrue);
    form.reset();
    await tester.pumpAndSettle();
    expect(second.text, 'Second baseline');
    expect(form.hasChanged, isFalse);
  });

  for (final clear in [false, true]) {
    testWidgets(
      'remount retains ${clear ? 'cleared' : 'edited'} field values',
      (tester) async {
        final form = FormFieldsController<_Field>(GlobalKey<FormState>());
        final scroll = ScrollController();
        addTearDown(form.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(_harness(form, scroll));
        await tester.enterText(
          find.byType(TextField),
          clear ? '' : 'Edited title',
        );
        form.updateValue<String>(
          _Field.category,
          clear ? null : 'Edited category',
        );
        await tester.pumpAndSettle();
        await _scrollAway(tester, scroll);
        expect(form.fieldKey(_Field.title).currentState, isNull);
        expect(form.fieldKey(_Field.category).currentState, isNull);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          form.getValue<String>(_Field.title),
          clear ? '' : 'Edited title',
        );
        expect(
          form.getValue<String>(_Field.category),
          clear ? null : 'Edited category',
        );
        expect(form.hasChanged, isTrue);
        form.reset();
        await tester.pumpAndSettle();
        expect(form.getValue<String>(_Field.title), 'Title baseline');
        expect(form.getValue<String>(_Field.category), 'Category baseline');
        expect(form.hasChanged, isFalse);
      },
    );
  }

  testWidgets('offscreen values remain readable and reset to field baselines', (
    tester,
  ) async {
    final form = FormFieldsController<_Field>(GlobalKey<FormState>());
    final scroll = ScrollController();
    addTearDown(form.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_harness(form, scroll));
    await tester.enterText(find.byType(TextField), 'Edited title');
    form.updateValue(_Field.category, 'Edited category');
    await _scrollAway(tester, scroll);
    expect(form.getValues(), {
      _Field.title: 'Edited title',
      _Field.category: 'Edited category',
    });
    expect(form.hasChanged, isTrue);
    form.reset();
    expect(form.getValue<String>(_Field.title), 'Title baseline');
    expect(form.getValue<String>(_Field.category), 'Category baseline');
    expect(form.hasChanged, isFalse);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Title baseline'), findsOneWidget);
    expect(find.text('Category baseline'), findsOneWidget);
  });

  testWidgets('switching form controllers uses the new entity baseline', (
    tester,
  ) async {
    final first = FormFieldsController<_Field>(
      GlobalKey<FormState>(),
      initialValues: {_Field.title: 'First entity'},
    );
    final second = FormFieldsController<_Field>(
      GlobalKey<FormState>(),
      initialValues: {_Field.title: 'Second entity'},
    );
    final scroll = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_harness(first, scroll));
    await tester.enterText(find.byType(TextField), 'Unsaved first entity');
    await tester.pumpWidget(_harness(second, scroll));
    expect(find.text('Second entity'), findsOneWidget);
    expect(second.hasChanged, isFalse);
  });
}
