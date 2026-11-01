// 职责: 验证自定义风格的新建、编辑、名称去重、软删除与提示词校验。
// 关联文件:
//   lib/shared/services/production/style_service.dart
//   lib/shared/database/daos/production_style_dao.dart
//   lib/shared/models/production/style.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/style.dart';
import 'package:reveric/shared/services/production/style_service.dart';

void main() {
  late AppDatabase db;
  late ProductionStyleService styles;
  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
    styles = ProductionStyleService(db);
  });
  tearDown(() => db.close());

  test('styles save, edit in place and soft-delete out of the list', () async {
    final style = await styles.save(
      name: ' Noir ',
      prompt: ProductionStylePrompt(before: 'Before', after: 'After'),
    );
    expect(style.name, 'Noir');
    expect((style.before, style.after), ('Before', 'After'));

    final edited = await styles.save(
      id: style.id,
      name: 'Noir 2',
      prompt: ProductionStylePrompt(before: 'B', after: ''),
    );
    expect(edited.id, style.id);
    expect((edited.name, edited.before, edited.after), ('Noir 2', 'B', ''));
    expect(await db.productionStyleDao.watchStyles().first, hasLength(1));

    await styles.delete(style.id);
    expect(await db.productionStyleDao.watchStyles().first, isEmpty);
    expect(await db.productionStyleDao.getStyle(style.id), isNull);
    expect(await db.select(db.productionStyles).get(), hasLength(1));
  });

  test('names stay unique among live styles', () async {
    final prompt = ProductionStylePrompt(before: 'B', after: 'A');
    final first = await styles.save(name: 'Noir', prompt: prompt);
    final second = await styles.save(name: 'Noir', prompt: prompt);
    final third = await styles.save(name: ' Noir ', prompt: prompt);
    expect([second.name, third.name], ['Noir (2)', 'Noir (3)']);

    // 保留自己的名字不算重名；改成别人的名字会补序号。
    expect(
      (await styles.save(id: first.id, name: 'Noir', prompt: prompt)).name,
      'Noir',
    );
    expect(
      (await styles.save(id: third.id, name: 'Noir', prompt: prompt)).name,
      'Noir (3)',
    );

    // 已删除的风格让出名字。
    await styles.delete(first.id);
    expect((await styles.save(name: 'Noir', prompt: prompt)).name, 'Noir');
  });

  test('styles require a name and some prompt text', () async {
    expect(
      () => ProductionStylePrompt(before: ' ', after: ''),
      throwsFormatException,
    );
    await expectLater(
      styles.save(
        name: ' ',
        prompt: ProductionStylePrompt(before: 'B', after: 'A'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      styles.save(
        id: 'missing',
        name: 'Noir',
        prompt: ProductionStylePrompt(before: 'B', after: 'A'),
      ),
      throwsArgumentError,
    );
  });
}
