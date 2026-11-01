// 职责: 小说信息表单字段枚举，定义创建/编辑作品的字段与校验器。
// 关联文件:
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/mobile/pages/novel_create_page.dart
//   lib/shared/models/content_kind.dart
//   lib/shared/models/novel_type.dart
//   lib/third/form/flutter_hook_form.dart
// 遵循的 Rules:
//   .agents/rules/form.md
import '../../third/form/flutter_hook_form.dart';

enum NovelFormField<T> implements FieldSchema {
  title<String>(validators: [RequiredValidator<String>(message: '请输入小说名称')]),
  authorName<String>(),
  description<String>(),
  // 保留自由文本契约，平台目录仅提供候选，旧分类和自定义值无需映射。
  category<String>(),
  type<String>(),
  contentKind<String>(),
  plannedEpisodeCount<String>(),
  sourceNovelId<String?>(),
  tags<List<String>>(),
  coverPath<String>();

  const NovelFormField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}
