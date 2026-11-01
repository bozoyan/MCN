// 职责: 测试 HookedFormField 自定义控件在表单校验后的错误展示。
// 关联文件:
//   lib/third/form/flutter_hook_form.dart

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/third/form/flutter_hook_form.dart';

enum _TestField<T> implements FieldSchema {
  name<String>(validators: [RequiredValidator<String>()]);

  const _TestField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

void main() {
  testWidgets('HookedFormField shows validation error after validate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(
              initialValues: {_TestField.name: ''},
            );

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  HookedFormField<_TestField, String>(
                    fieldHook: _TestField.name,
                    builder: (value, onChanged, error) {
                      return Text(error ?? 'no error');
                    },
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

    expect(find.text('no error'), findsOneWidget);

    await tester.tap(find.text('Validate'));
    await tester.pump();

    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('RequiredValidator rejects whitespace-only strings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HookBuilder(
          builder: (context) {
            final form = useForm<_TestField>(
              initialValues: {_TestField.name: '   '},
            );

            return HookedForm<_TestField>(
              form: form,
              child: Column(
                children: [
                  HookedFormField<_TestField, String>(
                    fieldHook: _TestField.name,
                    builder: (value, onChanged, error) {
                      return Text(error ?? 'no error');
                    },
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
  });
}
