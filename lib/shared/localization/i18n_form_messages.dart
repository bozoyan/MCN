import 'package:easy_localization/easy_localization.dart';

import '../../third/form/flutter_hook_form.dart';
import 'locale_keys.dart';

class I18nFormErrorMessages extends FormErrorMessages {
  const I18nFormErrorMessages();

  @override
  String get required => tr(LocaleKeys.formRequired);

  @override
  String get invalidEmail => tr(LocaleKeys.formInvalidEmail);

  @override
  String get invalidPhone => tr(LocaleKeys.formInvalidPhone);

  @override
  String get invalidPattern => tr(LocaleKeys.formInvalidPattern);

  @override
  String minLength(int length) =>
      tr(LocaleKeys.formMinLength, namedArgs: {'length': '$length'});

  @override
  String maxLength(int length) =>
      tr(LocaleKeys.formMaxLength, namedArgs: {'length': '$length'});

  @override
  String minItems(int count) =>
      tr(LocaleKeys.formMinItems, namedArgs: {'count': '$count'});

  @override
  String maxItems(int count) =>
      tr(LocaleKeys.formMaxItems, namedArgs: {'count': '$count'});

  @override
  String dateBefore(DateTime date) =>
      tr(LocaleKeys.formDateBefore, namedArgs: {'date': date.toString()});

  @override
  String dateAfter(DateTime date) =>
      tr(LocaleKeys.formDateAfter, namedArgs: {'date': date.toString()});
}
