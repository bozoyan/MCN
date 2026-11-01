// 职责: 验证文档边界、拆场身份、人物继承、跨场替换与稳定选区。
// 关联文件:
//   lib/shared/models/screenplay_document.dart
//   lib/shared/widgets/screenplay/editing_controller.dart
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/models/screenplay_document.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay_editing.dart';
import 'package:reveric/shared/widgets/screenplay/editing_controller.dart';

ScreenplayElement node(
  String id,
  String scene,
  ScreenplayElementType type, {
  String text = '',
  String? character,
}) => ScreenplayElement(
  id: id,
  episodeId: 'episode',
  sceneId: scene,
  type: type,
  text: text,
  characterId: character,
  timeLabel: type == ScreenplayElementType.scene_heading ? 'Night' : null,
);
ScreenplayDocument fixture() => ScreenplayDocument(
  episodeId: 'episode',
  screenplayId: 'screenplay',
  elements: [
    for (final id in ['a', 'b', 'c']) ...[
      node('heading_$id', id, ScreenplayElementType.scene_heading),
      node('body_$id', id, ScreenplayElementType.action, text: '$id body'),
    ],
  ],
  scenes: {
    for (final id in ['a', 'b', 'c'])
      id: ScreenplayDocumentScene(id: id, synopsis: id, cast: {'cast_$id'}),
  },
  evidence: {'r': 'b'},
);
void main() {
  ScreenplayEditingController editor(ScreenplayDocument doc) {
    final c = ScreenplayEditingController.forDocument(
      doc,
      ScreenplayElementKeys(),
    );
    c.onEdited = (_) {};
    c.confirmDelete = () async => true;
    c.confirmStructure = (_, _, _) async => true;
    addTearDown(c.dispose);
    return c;
  }

  test('删除首场标题走命令错误反馈，正文与撤销历史保持不变', () async {
    final original = fixture();
    final c = editor(original);
    final errors = <String>[];
    var confirmations = 0;
    c.onCommandError = errors.add;
    c.confirmStructure = (_, _, _) async {
      confirmations++;
      return true;
    };
    final selection = c.selection;
    await c.removeSceneHeading('a');
    expect(errors, ['first_scene_heading_required']);
    expect(confirmations, 0);
    expect(c.screenplay, same(original));
    expect(c.selection, selection);
    expect(c.canUndo, isFalse);
    await c.removeSceneHeading('b');
    expect(confirmations, 1);
    expect(c.screenplay!.sceneOrder, ['a', 'c']);
    c.undo();
    expect(c.screenplay!.sceneOrder, ['a', 'b', 'c']);
  });

  test(
    'reserved identities isolate external sets and expand only for new nodes',
    () {
      final original = fixture();
      final external = {'archived_element'};
      final document = ScreenplayDocument(
        episodeId: original.episodeId,
        screenplayId: original.screenplayId,
        elements: original.elements,
        scenes: original.scenes,
        reservedIds: UnmodifiableSetView(external),
      );
      external.clear();
      external.add('external_change');
      expect(document.reservedIds, contains('archived_element'));
      expect(document.reservedIds, isNot(contains('external_change')));
      expect(
        () => document.reservedIds.add('mutation'),
        throwsUnsupportedError,
      );

      final edited = document.withBodyEdits(
        [...document.elements]
          ..[1] = document.elements[1].copyWith(text: 'edited'),
      );
      expect(edited.reservedIds, same(document.reservedIds));
      final split = edited.split(const ScreenplayPosition('body_a', 2));
      expect(split.reservedIds, isNot(same(document.reservedIds)));
      expect(split.reservedIds, containsAll(document.reservedIds));
      expect(split.reservedIds, containsAll(split.newSceneIds));
      expect(split.reservedIds, containsAll(split.newElementIds));
      expect(document.reservedIds.intersection(split.newSceneIds), isEmpty);
      expect(document.reservedIds.intersection(split.newElementIds), isEmpty);
    },
  );

  test(
    'ordinary typing and undo history share the immutable reservation set',
    () async {
      final document = fixture();
      final c = editor(document);
      for (var i = 0; i < 20; i++) {
        c.edit([...c.value]..[1] = c.value[1].copyWith(text: 'edit $i'));
        await Future<void>.value();
        expect(c.screenplay!.reservedIds, same(document.reservedIds));
      }
      c.acknowledgeDocumentIds(const {}, const {'body_a': 'body_a'});
      for (var i = 19; i >= 0; i--) {
        expect(c.canUndo, isTrue);
        c.undo();
        expect(c.value[1].text, i == 0 ? 'a body' : 'edit ${i - 1}');
        expect(c.screenplay!.reservedIds, same(document.reservedIds));
      }
      expect(c.canUndo, isFalse);
      for (var i = 0; i < 20; i++) {
        c.redo();
        expect(c.value[1].text, 'edit $i');
        expect(c.screenplay!.reservedIds, same(document.reservedIds));
      }
    },
  );

  test(
    'same-ID save clears new flags without rebuilding nodes or reservations',
    () {
      final original = fixture();
      final draft = original.split(const ScreenplayPosition('body_a', 2));
      final c = editor(original);
      c.editDocument(draft);
      c.acknowledgeDocumentIds(
        {for (final id in draft.newSceneIds) id: id},
        {for (final id in draft.newElementIds) id: id},
      );
      expect(c.screenplay!.newSceneIds, isEmpty);
      expect(c.screenplay!.newElementIds, isEmpty);
      expect(c.screenplay!.reservedIds, same(draft.reservedIds));
      for (var i = 0; i < draft.elements.length; i++) {
        expect(c.value[i], same(draft.elements[i]));
        expect(c.screenplay!.elements[i], same(draft.elements[i]));
      }
      c.undo();
      expect(c.screenplay, same(original));
      c.redo();
      expect(c.screenplay!.newSceneIds, isEmpty);
      expect(c.screenplay!.newElementIds, isEmpty);
      expect(c.screenplay!.reservedIds, same(draft.reservedIds));
    },
  );

  test('actual remapping reserves final IDs without mutating the draft', () {
    final draft = fixture().split(const ScreenplayPosition('body_a', 2));
    final sceneId = draft.newSceneIds.single;
    final elementId = draft.newElementIds.first;
    final saved = draft.remapIdentities(
      {sceneId: 'scn_final'},
      {elementId: 'elm_final'},
    );
    expect(saved.scenes, contains('scn_final'));
    expect(saved.scenes, isNot(contains(sceneId)));
    expect(saved.elements.map((e) => e.id), contains('elm_final'));
    expect(saved.sceneElements('scn_final'), isNotEmpty);
    expect(saved.newSceneIds, isEmpty);
    expect(saved.newElementIds, isNot(contains(elementId)));
    expect(
      saved.reservedIds,
      containsAll({...draft.reservedIds, 'scn_final', 'elm_final'}),
    );
    expect(draft.reservedIds, isNot(contains('scn_final')));
    expect(draft.reservedIds, isNot(contains('elm_final')));
    expect(saved.elements.first, same(draft.elements.first));
  });

  test(
    'splitting dialogue duplicates the cue, not its identity or silent cast',
    () {
      final original = fixture();
      final d = original.copyWith(
        elements: [
          original.elements.first,
          node(
            'cue',
            'a',
            ScreenplayElementType.character,
            character: 'speaker',
          ),
          node(
            'speech',
            'a',
            ScreenplayElementType.dialogue,
            text: 'Hello world',
          ),
          ...original.elements.skip(2),
        ],
      );
      final split = d.split(const ScreenplayPosition('speech', 6));
      final id = split.sceneOrder[1];
      final moved = split.sceneElements(id);
      expect(moved.map((e) => e.type), [
        ScreenplayElementType.scene_heading,
        ScreenplayElementType.character,
        ScreenplayElementType.dialogue,
      ]);
      expect(moved[1].characterId, 'speaker');
      expect(moved[1].id, isNot('cue'));
      expect(moved.last.text, 'world');
      expect(split.newElementIds, moved.map((e) => e.id).toSet());
      expect(split.newElementIds, hasLength(3));
      expect(split.newElementIds, isNot(contains(id)));
      expect(split.sceneElements('a').last.id, 'speech');
      expect(split.scenes[id]!.cast, {'speaker'});
      expect(split.scenes['a']!.cast, {'cast_a'});
    },
  );
  test(
    'splits at start and end retain existing body IDs and permit an empty scene',
    () {
      final d = fixture();
      final start = d.split(const ScreenplayPosition('body_a', 0));
      expect(start.sceneElements('a'), hasLength(1));
      expect(start.sceneElements(start.sceneOrder[1]).last.id, 'body_a');
      expect(start.newElementIds, {
        start.sceneElements(start.sceneOrder[1]).first.id,
      });
      final end = d.split(const ScreenplayPosition('body_a', 6));
      expect(end.sceneElements(end.sceneOrder[1]), hasLength(1));
      expect(end.sceneElements('a').last.id, 'body_a');
      expect(end.newElementIds, {
        end.sceneElements(end.sceneOrder[1]).first.id,
      });
    },
  );
  test(
    'cross-scene replacement archives middle cast and absorbs only the retained suffix',
    () {
      final d = fixture();
      final next = d.replaceRange(
        const ScreenplayPosition('body_a', 2),
        const ScreenplayPosition('body_c', 2),
        'new',
      );
      expect(next.sceneOrder, ['a']);
      expect(next.scenes['a']!.synopsis, 'a');
      expect(next.scenes['a']!.cast, {'cast_a', 'cast_c'});
      expect(next.evidence['r'], isNull);
      expect(next.elements.last.id, 'body_c');
      expect(next.elements.last.sceneId, 'a');
    },
  );
  test(
    'whole-scene range preserves the following heading and first-title deletion fails',
    () {
      final d = fixture();
      final next = d.replaceRange(
        const ScreenplayPosition('heading_a', 0),
        const ScreenplayPosition('heading_b', 0),
        '',
      );
      expect(next.sceneOrder, ['b', 'c']);
      expect(
        () => d.replaceRange(
          const ScreenplayPosition('heading_a', 0),
          const ScreenplayPosition('heading_a', 1),
          '',
        ),
        throwsA(isA<ScreenplayServiceException>()),
      );
    },
  );
  test(
    'select all deletes scenes, retains episode and typing creates a first scene',
    () async {
      final c = editor(fixture());
      c.select(TextSelection(baseOffset: 0, extentOffset: c.source.length));
      await c.replaceSelection('');
      expect(c.value, isEmpty);
      expect(c.screenplay!.episodeId, 'episode');
      await c.replaceSelection('New opening');
      expect(c.value.first.isHeading, isTrue);
      expect(c.value.last.text, 'New opening');
      c.undo();
      expect(c.value, isEmpty);
      c.undo();
      expect(c.screenplay!.sceneOrder, ['a', 'b', 'c']);
    },
  );
  test(
    'readable find skips headings, replaces body matches once and preserves selection on rename',
    () async {
      final c = editor(fixture());
      c.refreshFindProjection();
      var skipped = 0;
      c.onFindSkipped = (n) => skipped = n;
      final ranges = RegExp('Night|body')
          .allMatches(c.findDocument.text)
          .map((m) => TextRange(start: m.start, end: m.end))
          .toList();
      await c.replaceFindRanges(ranges, 'changed');
      expect(skipped, 3);
      expect(
        c.value
            .where((e) => !e.isHeading)
            .every((e) => e.text.endsWith('changed')),
        isTrue,
      );
      c.undo();
      expect(c.value.last.text, 'c body');
      c.select(TextSelection.collapsed(offset: c.startOf(5) + 2));
      final selected = c.selection;
      c.locationNames = {'location': 'A very long new location'};
      c.refreshFindProjection();
      expect(c.selection, selected);
    },
  );
  test(
    'external insertion maps the caret by ID and invalidates saved history',
    () {
      final c = editor(fixture());
      c.edit([...c.value]..[1] = c.value[1].copyWith(text: 'local'));
      c.select(TextSelection.collapsed(offset: c.startOf(5) + 2));
      var invalid = 0;
      c.onHistoryInvalid = () => invalid++;
      final incoming = c.screenplay!.copyWith(
        elements: [
          ...c.value.take(2),
          node('new', 'a', ScreenplayElementType.action, text: 'extra'),
          ...c.value.skip(2),
        ],
      );
      c.acceptExternalDocument(incoming);
      expect(c.positionAt(c.selection.extentOffset), (index: 6, offset: 2));
      expect(c.canUndo, isFalse);
      expect(invalid, 1);
    },
  );
  test(
    'mobile native Enter creates a node while soft Enter stays in the paragraph',
    () async {
      final c = editor(fixture())..splitNativeNewlines = true;
      c.observeInput(
        1,
        const TextEditingValue(
          text: 'a \nbody',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextEditingValue(
          text: 'a body',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      c.edit([...c.value]..[1] = c.value[1].copyWith(text: 'a \nbody'));
      await Future<void>.delayed(Duration.zero);
      expect(c.screenplay!.sceneElements('a').map((e) => e.text), [
        '',
        'a ',
        'body',
      ]);
      await c.enter(soft: true);
      expect(c.value[2].text, '\nbody');
    },
  );
  test(
    'save feedback merges untouched external scenes without replacing newer input',
    () {
      final submitted = fixture();
      final saved = submitted.copyWith(
        elements: [
          for (final e in submitted.elements)
            e.id == 'body_b' ? e.copyWith(text: 'External B') : e,
        ],
      );
      final draft = submitted.copyWith(
        elements: [
          for (final e in submitted.elements)
            e.id == 'body_a' ? e.copyWith(text: 'Newer A') : e,
        ],
      );
      final rebased = draft.rebaseUnchanged(submitted, saved);
      expect(rebased.sceneElements('a').last.text, 'Newer A');
      expect(rebased.sceneElements('b').last.text, 'External B');
    },
  );
  test(
    'editDocument persists scene metadata changes even with identical elements',
    () {
      var edited = false;
      final original = fixture();
      final c = editor(original);
      c.onEdited = (_) => edited = true;

      final updatedScene = ScreenplayDocumentScene(
        id: 'a',
        synopsis: 'new synopsis',
        emotion: ['happy'],
        events: [
          {'title': 'event 1', 'summary': 'event summary'},
        ],
        cast: {'cast_a'},
      );
      final nextDoc = original.copyWith(
        scenes: {...original.scenes, 'a': updatedScene},
      );

      c.editDocument(nextDoc);
      expect(edited, isTrue);
      expect(c.screenplay!.scenes['a']!.synopsis, 'new synopsis');
      expect(c.screenplay!.scenes['a']!.emotion, ['happy']);
      expect(c.screenplay!.scenes['a']!.events, [
        {'title': 'event 1', 'summary': 'event summary'},
      ]);

      // Undo should restore previous metadata
      c.undo();
      expect(c.screenplay!.scenes['a']!.synopsis, 'a');
      expect(c.screenplay!.scenes['a']!.emotion, isNull);

      // Redo should restore updated metadata
      c.redo();
      expect(c.screenplay!.scenes['a']!.synopsis, 'new synopsis');
      expect(c.screenplay!.scenes['a']!.emotion, ['happy']);
    },
  );
}
