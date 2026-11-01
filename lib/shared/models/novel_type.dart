// 职责: 小说作品类型常量 — 定义分类值、各内容类型可新建的类型，以及来源小说文案映射。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/content_kind.dart
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/mobile/pages/novel_create_page.dart
//   lib/shared/localization/locale_keys.dart

import '../localization/locale_keys.dart';
import 'content_kind.dart';

const String novelTypeOriginal = 'original';
const String novelTypeAdaptation = 'adaptation';
const String novelTypeSequel = 'sequel';
const String novelTypeFanfic = 'fanfic';
const String novelTypeDerivative = 'derivative';
const String novelTypeMaterial = 'material';

const List<String> novelTypes = <String>[
  novelTypeOriginal,
  novelTypeAdaptation,
  novelTypeSequel,
  novelTypeFanfic,
  novelTypeDerivative,
  novelTypeMaterial,
];

/// 小说新建入口可选择的作品类型。二创范围尚未收敛，暂不开放新建；
/// 已存在或导入的二创作品仍保留原类型，避免破坏历史数据。
const List<String> creatableNovelWorkTypes = <String>[
  novelTypeOriginal,
  novelTypeSequel,
  novelTypeFanfic,
  novelTypeMaterial,
];

/// 剧本新建入口可选择的作品类型。改编只对剧本开放 —— 小说改编成小说没有产品入口，
/// 「把小说改编成剧本」才是真实场景。
const List<String> creatableScreenplayWorkTypes = <String>[
  novelTypeOriginal,
  novelTypeAdaptation,
  novelTypeSequel,
  novelTypeFanfic,
  novelTypeMaterial,
];

List<String> creatableNovelTypesFor(String contentKind) {
  return contentKind == contentKindScreenplay
      ? creatableScreenplayWorkTypes
      : creatableNovelWorkTypes;
}

/// 这些作品类型可以通过 `source_novel_id` 指向一本来源小说。
const Set<String> sourceLinkedNovelTypes = <String>{
  novelTypeAdaptation,
  novelTypeSequel,
  novelTypeFanfic,
  novelTypeDerivative,
};

bool novelTypeSupportsSourceNovel(String type) =>
    sourceLinkedNovelTypes.contains(type);

/// 来源小说字段的标题跟随作品类型 —— 「改编自小说」比通用的「来源小说」讲得清关系。
/// 不支持来源的类型返回 null，调用方据此隐藏整个字段。
String? sourceNovelLabelKey(String type) {
  return switch (type) {
    novelTypeAdaptation => LocaleKeys.librarySourceNovelAdaptation,
    novelTypeSequel => LocaleKeys.librarySourceNovelSequel,
    novelTypeFanfic => LocaleKeys.librarySourceNovelFanfic,
    novelTypeDerivative => LocaleKeys.librarySourceNovelDerivative,
    _ => null,
  };
}

/// 来源小说未选择时的占位文案，同样跟随作品类型。
String sourceNovelNoneKey(String type) {
  return switch (type) {
    novelTypeAdaptation => LocaleKeys.librarySourceNovelNoneAdaptation,
    novelTypeSequel => LocaleKeys.librarySourceNovelNoneSequel,
    novelTypeFanfic => LocaleKeys.librarySourceNovelNoneFanfic,
    novelTypeDerivative => LocaleKeys.librarySourceNovelNoneDerivative,
    _ => LocaleKeys.librarySourceNovelNone,
  };
}
