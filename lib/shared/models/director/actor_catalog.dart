// 职责: 定义导演台可注入的角色候选、模型体型与异步目录加载契约。
// 关联文件:
//   lib/shared/services/director/actor_catalog.dart
//   lib/shared/widgets/director/panels/actors.dart
//   lib/shared/services/screenplay/actor_catalog.dart

enum DirectorActorBody {
  male('actor.male.v1'),
  female('actor.female.v1');

  const DirectorActorBody(this.geometryKey);
  final String geometryKey;
}

class DirectorActor {
  const DirectorActor({
    required this.id,
    required this.name,
    this.body = DirectorActorBody.male,
  });

  /// 目录中的稳定标识，用于合并候选并绑定唯一布景实例；实例拥有独立 UUID。
  final String id;
  final String name;

  /// 调用方未指定时使用默认人偶，仅决定布景外形，不推断人物性别。
  final DirectorActorBody body;
}

class DirectorActorCatalog {
  const DirectorActorCatalog({this.initialActors, this.load});

  /// 立即可用的候选，并按此顺序保留在加载结果前面。
  /// null 且未提供 load 时使用内置角色；显式空列表表示空目录。
  final List<DirectorActor>? initialActors;

  /// 补充目录，按 ID 合并并更新同 ID 候选；不删除初始候选。
  /// 搜索由编辑器在合并后的目录中完成。
  final Future<List<DirectorActor>> Function()? load;
}
