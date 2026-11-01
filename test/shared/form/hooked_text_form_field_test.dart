// 职责: 测试 lib/shared/form/hooked_text_form_field.dart 的初始值、输入同步、校验与错误展示。
// 关联文件:
//   lib/shared/form/hooked_text_form_field.dart
//   lib/shared/form/form.dart

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/form/form.dart';
import 'package:reveric/shared/theme/theme.dart';

enum _TestField<T> implements FieldSchema {
  title<String>(validators: [RequiredValidator<String>()]),
  description<String>();

  const _TestField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

Widget _wrap(Widget child) => MaterialApp(
  theme: RevericThemeData.reveric.toThemeData(),
  home: RevericTheme(
    data: RevericThemeData.reveric,
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets(
    'HookedTextFormField displays initial value and updates form value on input',
    (tester) async {
      late FormFieldsController<_TestField> capturedForm;

      await tester.pumpWidget(
        _wrap(
          HookBuilder(
            builder: (context) {
              final form = useForm<_TestField>(
                initialValues: {
                  _TestField.title: 'Original Title',
                  _TestField.description: '',
                },
              );
              capturedForm = form;

              return HookedForm<_TestField>(
                form: form,
                child: Column(
                  children: [
                    const HookedTextFormField<_TestField>(
                      key: ValueKey('title_field'),
                      fieldHook: _TestField.title,
                      label: 'Title Label',
                      hintText: 'Enter title',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Title Label'), findsOneWidget);
      expect(find.text('Original Title'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('title_field')),
        'New Title',
      );
      await tester.pump();

      expect(capturedForm.getValue<String>(_TestField.title), 'New Title');
      expect(capturedForm.hasChanged, isTrue);
    },
  );

  testWidgets('HookedTextFormField shows validation errors and handles reset', (
    tester,
  ) async {
    late FormFieldsController<_TestField> capturedForm;

    await tester.pumpWidget(
      _wrap(
        HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(
              initialValues: {_TestField.title: ''},
            );
            capturedForm = form;

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  const HookedTextFormField<_TestField>(
                    key: ValueKey('title_field'),
                    fieldHook: _TestField.title,
                  ),
                  TextButton(
                    onPressed: form.validate,
                    child: const Text('Validate'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Validate'));
    await tester.pump();

    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('title_field')),
      'Valid Title',
    );
    await tester.pump();

    await tester.tap(find.text('Validate'));
    await tester.pump();

    expect(find.text('Required'), findsNothing);

    capturedForm.reset();
    await tester.pump();

    expect(find.text('Valid Title'), findsNothing);
  });

  testWidgets('HookedTextFormField displays forced errors from form.setError', (
    tester,
  ) async {
    late FormFieldsController<_TestField> capturedForm;

    await tester.pumpWidget(
      _wrap(
        HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(
              initialValues: {_TestField.title: 'Test'},
            );
            capturedForm = form;

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  const HookedTextFormField<_TestField>(
                    key: ValueKey('title_field'),
                    fieldHook: _TestField.title,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    capturedForm.setError(_TestField.title, 'Server Error Message');
    await tester.pump();

    expect(find.text('Server Error Message'), findsOneWidget);
  });

  testWidgets('HookedTextFormField works with external controller', (
    tester,
  ) async {
    late FormFieldsController<_TestField> capturedForm;

    await tester.pumpWidget(
      _wrap(
        HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(listen: false);
            final controller = useTextEditingController(text: 'External Text');
            capturedForm = form;

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  HookedTextFormField<_TestField>(
                    key: const ValueKey('ext_field'),
                    fieldKey: const ValueKey('ext_input'),
                    fieldHook: _TestField.description,
                    controller: controller,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('External Text'), findsOneWidget);
    // controller 自带的文本必须是 form 的初始基线：否则界面上明明有内容，
    // getValue 却读到 null，提交时会把用户看到的文字丢掉。
    expect(
      capturedForm.getValue<String>(_TestField.description),
      'External Text',
    );
    expect(capturedForm.hasChanged, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('ext_input')),
      'Edited Text',
    );
    await tester.pump();

    expect(
      capturedForm.getValue<String>(_TestField.description),
      'Edited Text',
    );
    expect(capturedForm.hasChanged, isTrue);
  });

  testWidgets('HookedTextFormField keeps IME composing on external write', (
    tester,
  ) async {
    late FormFieldsController<_TestField> capturedForm;

    await tester.pumpWidget(
      _wrap(
        HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(
              initialValues: {_TestField.description: ''},
              listen: false,
            );
            capturedForm = form;

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  const HookedTextFormField<_TestField>(
                    fieldHook: _TestField.description,
                    fieldKey: ValueKey('composing_input'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('composing_input')));
    await tester.pump();

    // 模拟中文 IME 组词中：composing 区间非空。
    tester
        .state<EditableTextState>(find.byType(EditableText))
        .updateEditingValue(
          const TextEditingValue(
            text: 'ni',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
    await tester.pump();

    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('composing_input')))
        .controller!;
    expect(controller.value.composing, const TextRange(start: 0, end: 2));

    // 组词期间的外部写入（模板填充、草稿消费等）不能清掉 composing，
    // 否则 macOS 会 discardMarkedText，用户正在打的拼音直接消失。
    capturedForm.updateValue(_TestField.description, 'nihao');
    await tester.pump();

    expect(controller.value.composing, const TextRange(start: 0, end: 2));
    expect(controller.text, 'ni');

    // 组词结束后被延后的写入才套用。
    controller.value = controller.value.copyWith(
      text: '你',
      selection: const TextSelection.collapsed(offset: 1),
      composing: TextRange.empty,
    );
    await tester.pump();

    expect(controller.text, 'nihao');
  });
}
