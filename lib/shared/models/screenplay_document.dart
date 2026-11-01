// 职责: 维护剧本文档的稳定位置、场次边界及可逆拆合场命令。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/shared/models/screenplay_editing.dart
//   lib/shared/services/screenplay_edit_orchestrator.dart
//   lib/shared/widgets/screenplay/editing_controller.dart

import 'package:collection/collection.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';
import 'screenplay.dart';
import 'screenplay_element.dart';

class ScreenplayPosition {
  const ScreenplayPosition(this.elementId, this.offset);
  final String elementId;
  final int offset;
}

class ScreenplayDocumentScene {
  ScreenplayDocumentScene({
    required this.id,
    this.beatId,
    this.synopsis = '',
    this.title = '',
    this.emotion,
    this.events,
    this.stage = screenplayStageDraft,
    Set<String> cast = const {},
  }) : cast = Set.unmodifiable(cast);
  final String id;
  final String? beatId;
  final String synopsis;
  final String title;
  final List<String>? emotion;
  final List<Map<String, dynamic>>? events;
  final String stage;
  final Set<String> cast;

  ScreenplayDocumentScene withCast(Set<String> value) =>
      ScreenplayDocumentScene(
        id: id,
        beatId: beatId,
        synopsis: synopsis,
        title: title,
        emotion: emotion,
        events: events,
        stage: stage,
        cast: value,
      );

  bool sameAs(ScreenplayDocumentScene? other) =>
      other != null &&
      id == other.id &&
      beatId == other.beatId &&
      synopsis == other.synopsis &&
      title == other.title &&
      const DeepCollectionEquality().equals(emotion, other.emotion) &&
      const DeepCollectionEquality().equals(events, other.events) &&
      stage == other.stage &&
      const SetEquality<String>().equals(cast, other.cast);
}

class ScreenplayDocument {
  ScreenplayDocument({
    required this.episodeId,
    required this.screenplayId,
    this.fullEpisode = true,
    this.previousSceneId,
    this.nextSceneId,
    required Iterable<ScreenplayElement> elements,
    required Map<String, ScreenplayDocumentScene> scenes,
    Map<String, String?> evidence = const {},
    Map<String, String> evidenceVersions = const {},
    Set<String> newSceneIds = const {},
    Set<String> newElementIds = const {},
    Set<String> reservedIds = const {},
  }) : elements = List.unmodifiable(elements),
       scenes = Map.unmodifiable(scenes),
       evidence = Map.unmodifiable(evidence),
       evidenceVersions = Map.unmodifiable(evidenceVersions),
       newSceneIds = Set.unmodifiable(newSceneIds),
       newElementIds = Set.unmodifiable(newElementIds),
       reservedIds = _ReservedIds.include(
         reservedIds,
         scenes.keys.followedBy(elements.map((e) => e.id).whereType<String>()),
       ) {
    validate();
  }
  final String episodeId;
  final String screenplayId;
  final bool fullEpisode;
  final String? previousSceneId;
  final String? nextSceneId;
  final List<ScreenplayElement> elements;
  final Map<String, ScreenplayDocumentScene> scenes;
  final Map<String, String?> evidence;
  final Map<String, String> evidenceVersions;

  /// 由编辑命令声明的新建身份；数据库读回和历史恢复默认为保留身份。
  final Set<String> newSceneIds;
  final Set<String> newElementIds;

  /// 读取时的完整存储身份与本草稿已使用身份，包含软删除及撤销中的节点。
  final Set<String> reservedIds;

  List<String> get sceneOrder => [
    for (final e in elements)
      if (e.isHeading) e.sceneId!,
  ];
  List<ScreenplayElement> sceneElements(String id) =>
      elements.where((e) => e.sceneId == id).toList();

  ScreenplayDocument copyWith({
    Iterable<ScreenplayElement>? elements,
    Map<String, ScreenplayDocumentScene>? scenes,
    Map<String, String?>? evidence,
    Set<String>? newSceneIds,
    Set<String>? newElementIds,
  }) => ScreenplayDocument(
    episodeId: episodeId,
    screenplayId: screenplayId,
    fullEpisode: fullEpisode,
    previousSceneId: previousSceneId,
    nextSceneId: nextSceneId,
    elements: elements ?? this.elements,
    scenes: scenes ?? this.scenes,
    evidence: evidence ?? this.evidence,
    evidenceVersions: evidenceVersions,
    newSceneIds: newSceneIds ?? this.newSceneIds,
    newElementIds: newElementIds ?? this.newElementIds,
    reservedIds: reservedIds,
  );

  ScreenplayDocument remapIdentities(
    Map<String, String> sceneIds,
    Map<String, String> elementIds,
  ) {
    final changesIdentity =
        sceneIds.entries.any((e) => e.key != e.value) ||
        elementIds.entries.any((e) => e.key != e.value);
    final remainingScenes = newSceneIds
        .where((id) => !sceneIds.containsKey(id))
        .toSet();
    final remainingElements = newElementIds
        .where((id) => !elementIds.containsKey(id))
        .toSet();
    // 同号确认仍需清除新建标记，但不必重建未变化的节点与保留集合。
    if (!changesIdentity &&
        remainingScenes.length == newSceneIds.length &&
        remainingElements.length == newElementIds.length) {
      return this;
    }
    final mappedScenes = <String, ScreenplayDocumentScene>{};
    for (final scene in scenes.values) {
      final id = sceneIds[scene.id] ?? scene.id;
      mappedScenes[id] = id == scene.id
          ? scene
          : ScreenplayDocumentScene(
              id: id,
              beatId: scene.beatId,
              synopsis: scene.synopsis,
              title: scene.title,
              emotion: scene.emotion,
              events: scene.events,
              stage: scene.stage,
              cast: scene.cast,
            );
    }
    return ScreenplayDocument(
      episodeId: episodeId,
      screenplayId: screenplayId,
      fullEpisode: fullEpisode,
      previousSceneId: sceneIds[previousSceneId] ?? previousSceneId,
      nextSceneId: sceneIds[nextSceneId] ?? nextSceneId,
      elements: [
        for (final e in elements)
          if ((elementIds[e.id] ?? e.id) == e.id &&
              (sceneIds[e.sceneId] ?? e.sceneId) == e.sceneId)
            e
          else
            e.copyWith(
              id: elementIds[e.id] ?? e.id,
              sceneId: sceneIds[e.sceneId] ?? e.sceneId,
            ),
      ],
      scenes: mappedScenes,
      evidence: {
        for (final e in evidence.entries) e.key: sceneIds[e.value] ?? e.value,
      },
      evidenceVersions: evidenceVersions,
      newSceneIds: remainingScenes,
      newElementIds: remainingElements,
      reservedIds: reservedIds,
    );
  }

  /// 合入保存期间未被本地修改的外部场次；后来的本地编辑仍以自己的节点为准。
  ScreenplayDocument rebaseUnchanged(
    ScreenplayDocument submitted,
    ScreenplayDocument saved,
  ) {
    final local = <String>{
      for (final id in {...scenes.keys, ...submitted.scenes.keys})
        if (!(scenes[id]?.sameAs(submitted.scenes[id]) ??
                !submitted.scenes.containsKey(id)) ||
            !sameScreenplayElements(
              sceneElements(id),
              submitted.sceneElements(id),
            ))
          id,
    };
    final order =
        const ListEquality<String>().equals(sceneOrder, submitted.sceneOrder)
        ? [...saved.sceneOrder]
        : [...sceneOrder];
    for (final id in saved.sceneOrder.where(
      (id) => !submitted.scenes.containsKey(id) && !order.contains(id),
    )) {
      final preceding = saved.sceneOrder
          .takeWhile((value) => value != id)
          .where(order.contains)
          .lastOrNull;
      order.insert(preceding == null ? 0 : order.indexOf(preceding) + 1, id);
    }
    order.removeWhere(
      (id) => !local.contains(id) && !saved.scenes.containsKey(id),
    );
    return ScreenplayDocument(
      episodeId: episodeId,
      screenplayId: screenplayId,
      fullEpisode: fullEpisode,
      previousSceneId: saved.previousSceneId,
      nextSceneId: saved.nextSceneId,
      elements: [
        for (final id in order)
          ...(local.contains(id) ? sceneElements(id) : saved.sceneElements(id)),
      ],
      scenes: {
        for (final id in order)
          id: (local.contains(id) ? scenes[id] : saved.scenes[id])!,
      },
      evidence: {
        for (final id in {...evidence.keys, ...saved.evidence.keys})
          id: evidence[id] != submitted.evidence[id]
              ? evidence[id]
              : saved.evidence[id],
      },
      evidenceVersions: saved.evidenceVersions,
      newSceneIds: newSceneIds,
      newElementIds: newElementIds,
      reservedIds: {...reservedIds, ...saved.reservedIds},
    );
  }

  void validate() {
    final ids = <String>{};
    final headings = <String>{};
    String? scene;
    var hasCharacter = false;
    for (final element in elements) {
      element.validateShape();
      if (element.id == null ||
          !ids.add(element.id!) ||
          element.episodeId != episodeId ||
          !scenes.containsKey(element.sceneId)) {
        throw const ScreenplayServiceException(
          'invalid_screenplay_document',
          'Invalid document identity or ownership.',
        );
      }
      if (element.isHeading) {
        if (!headings.add(element.sceneId!)) {
          throw const ScreenplayServiceException(
            'invalid_screenplay_document',
            'Duplicate scene heading.',
          );
        }
        scene = element.sceneId;
        hasCharacter = false;
      } else {
        if (scene == null || scene != element.sceneId) {
          throw const ScreenplayServiceException(
            'invalid_screenplay_document',
            'Scene blocks must be contiguous.',
          );
        }
        switch (element.type) {
          case ScreenplayElementType.character:
            hasCharacter = true;
          case ScreenplayElementType.dialogue:
          case ScreenplayElementType.parenthetical:
            if (!hasCharacter) {
              throw const ScreenplayServiceException(
                'dialogue_character_required',
                'Dialogue requires a character in the same scene.',
              );
            }
          default:
            hasCharacter = false;
        }
      }
    }
    if (!const SetEquality<String>().equals(headings, scenes.keys.toSet())) {
      throw const ScreenplayServiceException(
        'invalid_screenplay_document',
        'Every scene needs one heading.',
      );
    }
  }

  ScreenplayDocument withBodyEdits(List<ScreenplayElement> nodes) {
    final nextScenes = {...scenes};
    for (final element in nodes) {
      if (element.characterId != null) {
        final scene = nextScenes[element.sceneId]!;
        nextScenes[scene.id] = scene.withCast({
          ...scene.cast,
          element.characterId!,
        });
      }
    }
    return copyWith(
      elements: nodes,
      scenes: nextScenes,
      newElementIds: {
        ...newElementIds,
        ...nodes
            .map((e) => e.id!)
            .toSet()
            .difference(elements.map((e) => e.id!).toSet()),
      },
    );
  }

  ScreenplayDocument split(ScreenplayPosition at) {
    final index = elements.indexWhere((e) => e.id == at.elementId);
    if (index < 0 || elements[index].isHeading) {
      throw const ScreenplayServiceException(
        'invalid_split_position',
        'Split requires a body position.',
      );
    }
    final current = elements[index];
    final oldScene = scenes[current.sceneId]!;
    final heading = elements.firstWhere(
      (e) => e.isHeading && e.sceneId == oldScene.id,
    );
    final offset = at.offset;
    final length = current.isObject ? 1 : current.text.length;
    if (offset < 0 || offset > length) {
      throw const ScreenplayServiceException(
        'invalid_split_position',
        'Split offset is outside the node.',
      );
    }
    final reserved = {...reservedIds};
    final sceneId = allocateScreenplayDraftId(
      ShortEntityIdType.screenplayScene,
      reserved,
    );
    final allocatedElements = <String>{};
    String allocateElement() {
      final id = allocateScreenplayDraftId(
        ShortEntityIdType.screenplayElement,
        reserved,
      );
      allocatedElements.add(id);
      return id;
    }

    var end = index + 1;
    while (end < elements.length && elements[end].sceneId == oldScene.id) {
      end++;
    }
    final prefix = elements.take(index).toList();
    final moved = <ScreenplayElement>[];
    if (offset == 0) {
      moved.add(current);
    } else if (offset == length) {
      prefix.add(current);
    } else {
      prefix.add(current.copyWith(text: current.text.substring(0, offset)));
      moved.add(
        current.copyWith(
          id: allocateElement(),
          text: current.text.substring(offset),
        ),
      );
    }
    moved.addAll(elements.sublist(index + 1, end));
    if (moved.isNotEmpty &&
        (moved.first.type == ScreenplayElementType.dialogue ||
            moved.first.type == ScreenplayElementType.parenthetical)) {
      final cue = elements
          .take(index + 1)
          .lastWhere((e) => e.type == ScreenplayElementType.character);
      moved.insert(0, cue.copyWith(id: allocateElement()));
    }
    final newHeading = heading.copyWith(
      id: allocateElement(),
      sceneId: sceneId,
    );
    return copyWith(
      newSceneIds: {...newSceneIds, sceneId},
      newElementIds: {...newElementIds, ...allocatedElements},
      elements: [
        ...prefix,
        newHeading,
        ...moved.map((e) => e.copyWith(sceneId: sceneId)),
        ...elements.skip(end),
      ],
      scenes: {
        ...scenes,
        sceneId: ScreenplayDocumentScene(
          id: sceneId,
          beatId: oldScene.beatId,
          cast: moved.map((e) => e.characterId).whereType<String>().toSet(),
        ),
      },
    );
  }

  ScreenplayDocument merge(String absorbedId) {
    final order = sceneOrder;
    final position = order.indexOf(absorbedId);
    if (position <= 0) {
      throw const ScreenplayServiceException(
        'first_scene_heading_required',
        'The first scene heading cannot be removed on its own.',
      );
    }
    final targetId = order[position - 1];
    final target = scenes[targetId]!;
    final absorbed = scenes[absorbedId]!;
    final nextScenes = {...scenes}..remove(absorbedId);
    nextScenes[targetId] = target.withCast({...target.cast, ...absorbed.cast});
    return copyWith(
      elements: [
        for (final e in elements)
          if (e.sceneId != absorbedId)
            e
          else if (!e.isHeading)
            e.copyWith(sceneId: targetId),
      ],
      scenes: nextScenes,
      evidence: {
        for (final entry in evidence.entries)
          entry.key: entry.value == absorbedId ? null : entry.value,
      },
    );
  }

  ScreenplayDocument replaceRange(
    ScreenplayPosition start,
    ScreenplayPosition end,
    String text,
  ) {
    final first = elements.indexWhere((e) => e.id == start.elementId);
    final last = elements.indexWhere((e) => e.id == end.elementId);
    if (first < 0 || last < first) {
      throw const ScreenplayServiceException(
        'invalid_screenplay_selection',
        'Selection is outside the document.',
      );
    }
    final left = elements[first];
    final right = elements[last];
    final prefix = elements.take(first).toList();
    if (left.isObject) {
      if (start.offset == 1) {
        prefix.add(left);
      }
    } else if (start.offset > 0) {
      prefix.add(left.copyWith(text: left.text.substring(0, start.offset)));
    }
    final suffix = <ScreenplayElement>[];
    if (end.offset == 0 && first != last) {
      suffix.add(right);
    } else if (!right.isObject && end.offset < right.text.length) {
      suffix.add(right.copyWith(text: right.text.substring(end.offset)));
    }
    suffix.addAll(elements.skip(last + 1));
    final targetId = prefix.where((e) => e.isHeading).lastOrNull?.sceneId;
    final absorbed = <String>{};
    final migrated = <ScreenplayElement>[];
    var beforeHeading = true;
    for (final element in suffix) {
      if (element.isHeading) {
        beforeHeading = false;
      }
      if (beforeHeading) {
        if (targetId == null) {
          throw const ScreenplayServiceException(
            'first_scene_heading_required',
            'The first heading cannot leave body text without a scene.',
          );
        }
        if (element.sceneId != targetId) {
          absorbed.add(element.sceneId!);
        }
        migrated.add(element.copyWith(sceneId: targetId));
      } else {
        migrated.add(element);
      }
    }
    if (text.isNotEmpty) {
      if (targetId == null) {
        throw const ScreenplayServiceException(
          'first_scene_heading_required',
          'Replacement text requires a scene heading.',
        );
      }
      if (prefix.isNotEmpty &&
          !prefix.last.isObject &&
          prefix.last.id == left.id) {
        prefix[prefix.length - 1] = prefix.last.copyWith(
          text: prefix.last.text + text,
        );
      } else {
        prefix.add(
          ScreenplayElement(
            id: allocateScreenplayDraftId(ShortEntityIdType.screenplayElement, {
              ...reservedIds,
            }),
            episodeId: episodeId,
            sceneId: targetId,
            type: ScreenplayElementType.action,
            text: text,
          ),
        );
      }
    }
    final nodes = [...prefix, ...migrated];
    final retained = nodes
        .where((e) => e.isHeading)
        .map((e) => e.sceneId!)
        .toSet();
    final nextScenes = {for (final id in retained) id: scenes[id]!};
    if (targetId != null) {
      nextScenes[targetId] = scenes[targetId]!.withCast({
        ...scenes[targetId]!.cast,
        for (final id in absorbed) ...scenes[id]!.cast,
        ...nodes
            .where((e) => e.sceneId == targetId)
            .map((e) => e.characterId)
            .whereType<String>(),
      });
    }
    return copyWith(
      elements: nodes,
      newElementIds: {
        ...newElementIds,
        ...nodes
            .map((e) => e.id!)
            .toSet()
            .difference(elements.map((e) => e.id!).toSet()),
      },
      scenes: nextScenes,
      evidence: {
        for (final entry in evidence.entries)
          entry.key:
              entry.value != null &&
                  scenes.containsKey(entry.value) &&
                  !retained.contains(entry.value)
              ? null
              : entry.value,
      },
    );
  }

  ScreenplayDocument deleteScenes(Set<String> ids) => copyWith(
    elements: elements.where((e) => !ids.contains(e.sceneId)),
    scenes: {...scenes}..removeWhere((id, _) => ids.contains(id)),
    evidence: {
      for (final entry in evidence.entries)
        entry.key: ids.contains(entry.value) ? null : entry.value,
    },
  );

  ScreenplayDocument moveBefore(String id, String? anchorId) {
    if (!scenes.containsKey(id) ||
        id == anchorId ||
        (anchorId != null && !scenes.containsKey(anchorId))) {
      throw const ScreenplayServiceException(
        'invalid_scene_anchor',
        'Invalid scene anchor.',
      );
    }
    final rest = elements.where((e) => e.sceneId != id).toList();
    final index = anchorId == null
        ? rest.length
        : rest.indexWhere((e) => e.sceneId == anchorId);
    rest.insertAll(index, sceneElements(id));
    return copyWith(elements: rest);
  }

  ScreenplayDocument createFirstScene({String text = ''}) {
    if (elements.isNotEmpty || scenes.isNotEmpty) {
      throw const ScreenplayServiceException(
        'invalid_screenplay_document',
        'Document is not empty.',
      );
    }
    final reserved = {...reservedIds};
    final id = allocateScreenplayDraftId(
      ShortEntityIdType.screenplayScene,
      reserved,
    );
    final headingId = allocateScreenplayDraftId(
      ShortEntityIdType.screenplayElement,
      reserved,
    );
    final bodyId = allocateScreenplayDraftId(
      ShortEntityIdType.screenplayElement,
      reserved,
    );
    return copyWith(
      newSceneIds: {id},
      newElementIds: {headingId, bodyId},
      scenes: {id: ScreenplayDocumentScene(id: id)},
      elements: [
        ScreenplayElement(
          id: headingId,
          episodeId: episodeId,
          sceneId: id,
          type: ScreenplayElementType.scene_heading,
          timeLabel: '',
        ),
        ScreenplayElement(
          id: bodyId,
          episodeId: episodeId,
          sceneId: id,
          type: ScreenplayElementType.action,
          text: text,
        ),
      ],
    );
  }
}

/// 只包装本文件持有的集合；无新增身份时可安全地供文档和历史共享。
class _ReservedIds extends UnmodifiableSetView<String> {
  _ReservedIds(super.source);

  static Set<String> include(Set<String> reserved, Iterable<String> ids) {
    // 外部传入的 Set 即使是只读 view，底层也可能被修改，必须先隔离。
    if (reserved is _ReservedIds && ids.every(reserved.contains)) {
      return reserved;
    }
    return _ReservedIds({...reserved, ...ids});
  }
}

/// 草稿先排除同批身份；保存时再查询完整存储表并以严格 INSERT 确认。
String allocateScreenplayDraftId(
  ShortEntityIdType type,
  Set<String> reserved, {
  ShortEntityIdBuilder buildId = buildShortEntityId,
}) {
  for (var attempt = 0; attempt < shortEntityIdMaxAttempts; attempt++) {
    final id = buildId(type);
    if (reserved.add(id)) {
      return id;
    }
  }
  throw ShortEntityIdAllocationException(type);
}

bool sameScreenplayElements(
  List<ScreenplayElement> a,
  List<ScreenplayElement> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.type != y.type ||
        x.sceneId != y.sceneId ||
        x.episodeId != y.episodeId ||
        x.text != y.text ||
        x.characterId != y.characterId ||
        x.extension != y.extension ||
        x.interiorExterior != y.interiorExterior ||
        x.locationId != y.locationId ||
        x.timeLabel != y.timeLabel) {
      return false;
    }
  }
  return true;
}
