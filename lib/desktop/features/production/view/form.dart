// 职责: 定义派生面板字段与从表单读取的参数快照。
// 关联文件:
//   lib/desktop/features/production/view/panel.dart
//   lib/shared/models/production/view_presets.dart
import '../../../../shared/form/form.dart';
import '../../../../shared/models/production/view_presets.dart';

enum ViewField<T> implements FieldSchema {
  yaw<int>(),
  pitch<int>(),
  framing<CameraFraming>(),
  direction<LightDirection>(),
  brightness<LightBrightness>(),
  texture<LightTexture>(),
  temperature<LightTemperature>(),
  description<String>();

  const ViewField();
  @override
  List<Validator<dynamic>>? get validators => null;
}

ViewPresetArgs viewArgs(FormFieldsController<ViewField> form) => ViewPresetArgs(
  yaw: form.getValue<int>(ViewField.yaw)!,
  pitch: form.getValue<int>(ViewField.pitch)!,
  framing: form.getValue<CameraFraming>(ViewField.framing)!,
  direction: form.getValue<LightDirection>(ViewField.direction)!,
  brightness: form.getValue<LightBrightness>(ViewField.brightness)!,
  texture: form.getValue<LightTexture>(ViewField.texture)!,
  temperature: form.getValue<LightTemperature>(ViewField.temperature)!,
  description: form.getValue<String>(ViewField.description) ?? '',
);
