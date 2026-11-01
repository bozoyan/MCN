// 职责: 定义导演属性与关键帧表单字段的稳定标识和必填校验。
// 关联文件:
//   lib/shared/widgets/director/inspector.dart
//   lib/shared/widgets/director/track_editor.dart
//   lib/third/form/flutter_hook_form.dart
import '../../../third/form/flutter_hook_form.dart';

enum DirectorField<T> implements FieldSchema {
  name<String>(validators: [RequiredValidator<String>()]),
  position<String>(validators: [RequiredValidator<String>()]),
  rotation<String>(validators: [RequiredValidator<String>()]),
  scale<String>(validators: [RequiredValidator<String>()]),
  color<String>(validators: [RequiredValidator<String>()]),
  cameraPosition<String>(validators: [RequiredValidator<String>()]),
  target<String>(validators: [RequiredValidator<String>()]),
  focal<String>(validators: [RequiredValidator<String>()]),
  duration<String>(validators: [RequiredValidator<String>()]),
  start<String>(validators: [RequiredValidator<String>()]),
  end<String>(validators: [RequiredValidator<String>()]),
  frame<String>(validators: [RequiredValidator<String>()]),
  value<String>(validators: [RequiredValidator<String>()]);

  const DirectorField({this.validators = const []});
  @override
  final List<Validator<T>> validators;
}
