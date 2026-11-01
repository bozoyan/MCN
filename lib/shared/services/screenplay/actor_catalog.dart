// 职责: 将作品人物库转换成通用导演台角色候选。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/director/actor_catalog.dart
//   lib/shared/widgets/screenplay/director_host.dart
import '../../database/novel_content_database.dart';
import '../../models/director/actor_catalog.dart';

/// 调度不属于任何场次，角色从作品的全部人物里按需添加。
DirectorActorCatalog loadScreenplayActorCatalog(
  NovelContentDatabase database,
) => DirectorActorCatalog(
  initialActors: const [],
  load: () async => [
    for (final profile in await database.characterProfileDao.getAll())
      _actor(profile),
  ],
);

DirectorActor _actor(CharacterProfile profile) => DirectorActor(
  id: profile.id,
  name: profile.name,
  body: switch (profile.gender) {
    characterGenderMale => DirectorActorBody.male,
    characterGenderFemale => DirectorActorBody.female,
    _ => DirectorActorBody.male,
  },
);
