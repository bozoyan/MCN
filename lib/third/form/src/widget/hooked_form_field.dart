import 'package:flutter/material.dart';

import '../hooks/use_form_context.dart';
import '../models/field_schema.dart';
import '../models/form_field_controller.dart';
import '../validators/validators.dart';

/// A form field that integrates with flutter_hook_form.
class HookedFormField<F extends FieldSchema, T> extends StatelessWidget {
  /// Creates a [HookedFormField] that gets the form from context.
  ///
  /// This widget wraps a standard [FormField] and connects it to a [FormFieldsController].
  ///
  /// Use the recommended [HookedForm] to wrap your form to provide the form
  /// controller to this widget. If not, use [HookedFormField.explicit] to provide
  /// the form controller explicitly.
  ///
  /// ```dart
  /// /// Recommended
  /// HookedForm( // <--- Form is provided via context
  ///   form: form,
  ///   child: HookedFormField<MyFormSchema, String>(
  ///     fieldKey: MyFormSchema.fieldKey,
  ///     builder: ({value, onChanged, error}){
  ///       return MyWidget(value: value, onChanged: onChanged, error: error);
  ///     },
  ///   ),
  /// )
  ///
  /// /// Alternative
  /// Form(
  ///   key: form.key,
  ///   child: HookedFormField.explicit(
  ///     form: form, // <--- Form is provided explicitly
  ///     fieldKey: MyFormSchema.fieldKey,
  ///     builder: ({value, onChanged, error}){
  ///       return MyWidget(value: value, onChanged: onChanged, error: error);
  ///     },
  ///   ),
  /// )
  /// ```
  const HookedFormField({
    super.key,
    required this.fieldHook,
    required this.builder,
    this.forceErrorText,
    this.validator,
    this.autovalidateMode,
    this.enabled = true,
    this.initialValue,
    this.onSaved,
    this.restorationId,
    this.notifyOnChange = false,
  }) : _form = null;

  /// Creates a [HookedFormField] with an explicitly provided form.
  ///
  /// Consider using [HookedFormField.explicit] if you did not use [HookedForm] to
  /// wrap your form or use [HookedFormProvider] to provide the form.
  const HookedFormField.explicit({
    super.key,
    required this.fieldHook,
    required this.builder,
    required FormFieldsController form,
    this.forceErrorText,
    this.validator,
    this.autovalidateMode,
    this.enabled = true,
    this.initialValue,
    this.onSaved,
    this.restorationId,
    this.notifyOnChange = false,
  }) : _form = form;

  /// The form controller, if provided directly.
  final FormFieldsController? _form;

  /// The field identifier from the form schema.
  final F fieldHook;

  /// Builder function to create the form field widget.
  ///
  /// The builder function receives a map with the following parameters:
  /// - `value`: The current value of the field.
  /// - `onChanged`: A function to update the value of the field.
  /// - `error`: The error message of the field.
  final Widget Function(T? value, void Function(T?)? onChanged, String? error)
  builder;

  /// Optional error text to force the field into an error state.
  final String? forceErrorText;

  /// Optional validator function that overrides the form's validators.
  final String? Function(T?)? validator;

  /// Controls when auto-validation occurs.
  final AutovalidateMode? autovalidateMode;

  /// Whether the field is enabled.
  final bool enabled;

  /// Initial value for the field.
  final T? initialValue;

  /// Callback when the form is saved.
  final void Function(T?)? onSaved;

  /// Restoration ID for saving and restoring the field state.
  final String? restorationId;

  /// Whether to notify form listeners when the field value changes.
  ///
  /// Default to `false` to avoid any unwanted rebuilds.
  final bool notifyOnChange;

  @override
  Widget build(BuildContext context) {
    final form = _form ?? useFormContext<FieldSchema>(context);
    final effectiveInitialValue =
        form.getInitialValue<T>(fieldHook) ?? initialValue;

    return _EditingFormField<T>(
      key: form.fieldKey(fieldHook),
      editingValue: form.registerField<T>(
        fieldHook,
        initialValue: effectiveInitialValue,
      ),
      validator:
          validator ?? form.validators(fieldHook)?.resolveMessage<T>(context),
      forceErrorText:
          forceErrorText ??
          form
              .getFieldForcedError(fieldHook)
              .localize(context, form.getValue(fieldHook)),
      autovalidateMode: autovalidateMode,
      enabled: enabled,
      initialValue: effectiveInitialValue,
      onSaved: onSaved,
      restorationId: restorationId,
      builder: (field) {
        return builder(
          form.getValue(fieldHook),
          (value) =>
              form.updateValue<T>(fieldHook, value, notify: notifyOnChange),
          field.errorText,
        );
      },
    );
  }
}

/// Preserve the reset baseline while restoring edits when a field remounts.
class _EditingFormField<T> extends FormField<T> {
  const _EditingFormField({
    super.key,
    required this.editingValue,
    required super.builder,
    super.initialValue,
    super.validator,
    super.forceErrorText,
    super.autovalidateMode,
    super.enabled,
    super.onSaved,
    super.restorationId,
  });

  final T? editingValue;

  @override
  FormFieldState<T> createState() => _EditingFormFieldState<T>();
}

class _EditingFormFieldState<T> extends FormFieldState<T> {
  @override
  void initState() {
    super.initState();
    setValue((widget as _EditingFormField<T>).editingValue);
  }
}
