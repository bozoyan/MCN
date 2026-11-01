// 职责: 验证作品类型兼容集合、各内容类型可新建的集合与来源小说文案映射的边界。
// 关联文件:
//   lib/shared/models/novel_type.dart
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/mobile/pages/novel_create_page.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/novel_type.dart';

void main() {
  test('derivative remains a supported legacy type but is not creatable', () {
    expect(novelTypes, contains(novelTypeAdaptation));
    expect(novelTypes, contains(novelTypeDerivative));
    for (final kind in contentKinds) {
      expect(
        creatableNovelTypesFor(kind),
        isNot(contains(novelTypeDerivative)),
      );
    }
  });

  test('adaptation is creatable for screenplays only', () {
    expect(
      creatableNovelTypesFor(contentKindScreenplay),
      contains(novelTypeAdaptation),
    );
    expect(
      creatableNovelTypesFor(contentKindNovel),
      isNot(contains(novelTypeAdaptation)),
    );
  });

  test('both content kinds share the remaining creatable types', () {
    const shared = [
      novelTypeOriginal,
      novelTypeSequel,
      novelTypeFanfic,
      novelTypeMaterial,
    ];
    expect(creatableNovelTypesFor(contentKindNovel), containsAll(shared));
    expect(creatableNovelTypesFor(contentKindScreenplay), containsAll(shared));
  });

  test('unknown content kinds fall back to the novel set', () {
    expect(creatableNovelTypesFor('unknown'), creatableNovelWorkTypes);
  });

  test('editing keeps the creatable set for the content kind', () {
    expect(creatableNovelTypesFor(contentKindNovel), creatableNovelWorkTypes);
    expect(
      creatableNovelTypesFor(contentKindScreenplay),
      creatableScreenplayWorkTypes,
    );
  });

  test('creation and editing exclude unsupported historical types', () {
    expect(
      creatableNovelTypesFor(contentKindNovel),
      isNot(contains(novelTypeAdaptation)),
    );
    expect(
      creatableNovelTypesFor(contentKindNovel),
      isNot(contains(novelTypeDerivative)),
    );
  });

  test('editing ignores unknown current types', () {
    expect(creatableNovelTypesFor(contentKindNovel), creatableNovelWorkTypes);
  });

  test('only lineage work types support a source novel', () {
    expect(novelTypeSupportsSourceNovel(novelTypeAdaptation), isTrue);
    expect(novelTypeSupportsSourceNovel(novelTypeSequel), isTrue);
    expect(novelTypeSupportsSourceNovel(novelTypeFanfic), isTrue);
    expect(novelTypeSupportsSourceNovel(novelTypeDerivative), isTrue);
    expect(novelTypeSupportsSourceNovel(novelTypeOriginal), isFalse);
    expect(novelTypeSupportsSourceNovel(novelTypeMaterial), isFalse);
  });

  test('source novel copy follows the work type', () {
    expect(
      sourceNovelLabelKey(novelTypeAdaptation),
      LocaleKeys.librarySourceNovelAdaptation,
    );
    expect(
      sourceNovelNoneKey(novelTypeSequel),
      LocaleKeys.librarySourceNovelNoneSequel,
    );
    // 不支持来源的类型没有标题，调用方据此隐藏整个字段。
    expect(sourceNovelLabelKey(novelTypeOriginal), isNull);
    expect(sourceNovelLabelKey(novelTypeMaterial), isNull);
    expect(
      sourceNovelNoneKey(novelTypeOriginal),
      LocaleKeys.librarySourceNovelNone,
    );
  });

  test('every source-linked type has both label and empty-state copy', () {
    for (final type in sourceLinkedNovelTypes) {
      expect(sourceNovelLabelKey(type), isNotNull, reason: type);
      expect(
        sourceNovelNoneKey(type),
        isNot(LocaleKeys.librarySourceNovelNone),
        reason: type,
      );
    }
  });
}
