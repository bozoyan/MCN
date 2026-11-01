// 职责: 原子维护剧本文档节点、全文选区与撤销历史，并将编辑投影供查找替换使用。
// 关联文件:
//   lib/shared/models/screenplay_editing.dart
//   lib/shared/models/screenplay_element.dart
//   lib/shared/widgets/screenplay/editing_scope.dart
//   lib/shared/services/document_save_coordinator.dart
// 遵循的 Rules:
//   .agents/rules/text-input-ime.md

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import '../../models/screenplay_editing.dart';
import '../../models/screenplay_element.dart';
import '../../models/screenplay_document.dart';
import '../../models/screenplay.dart';
import '../../models/screenplay_element_render.dart';
import '../../utils/short_entity_id.dart';

/// 元素分隔符区别于 Shift+Enter 的软换行；角色引用在编辑投影中是不可拆分对象。
const screenplayElementSeparator = '\u2029';
const screenplayCharacterObject = '\uFFFC';

class ScreenplayEditingController
    extends ValueNotifier<List<ScreenplayElement>> {
  ScreenplayEditingController(List<ScreenplayElement> elements, this.keys)
    : super([...elements]) {
    document.value = TextEditingValue(
      text: source,
      selection: const TextSelection.collapsed(offset: 0),
    );
    document.addListener(_documentChanged);
    _committed = [...elements];
  }

  factory ScreenplayEditingController.forDocument(
    ScreenplayDocument value,
    ScreenplayElementKeys keys,
  ) {
    return ScreenplayEditingController(value.elements, keys)
      ..screenplay = value;
  }

  ScreenplayDocument? screenplay;
  ScreenplayDocument? _nextDocument;
  Future<bool> Function(
    ScreenplayDocument before,
    ScreenplayDocument after,
    bool expanded,
  )?
  confirmStructure;
  Future<bool> Function(
    ScreenplayDocument before,
    ScreenplayDocument after,
    String sceneId,
  )?
  confirmDeleteScene;
  Map<String, String> locationNames = {};
  void Function(String code)? onCommandError;
  VoidCallback? onHistoryInvalid;
  void Function(String id)? onFindHeading;
  bool splitNativeNewlines = false;
  final ScreenplayElementKeys keys;
  final document = TextEditingController();
  final findDocument = TextEditingController();
  void Function(int count)? onFindSkipped;
  List<int> _findStarts = [];
  List<ScreenplayElement>? _findValue;
  Map<String, String> _findCharacters = {};
  Map<String, String> _findLocations = {};

  void refreshFindProjection() {
    if (screenplay == null) {
      return;
    }
    if (identical(_findValue, value) &&
        const MapEquality<String, String>().equals(
          _findCharacters,
          characterNames,
        ) &&
        const MapEquality<String, String>().equals(
          _findLocations,
          locationNames,
        )) {
      return;
    }
    _findValue = value;
    _findCharacters = Map.of(characterNames);
    _findLocations = Map.of(locationNames);
    final buffer = StringBuffer();
    _findStarts = [];
    for (var i = 0; i < value.length; i++) {
      if (i > 0) {
        buffer.write('\n');
      }
      _findStarts.add(buffer.length);
      buffer.write(
        value[i].isObject
            ? renderScreenplayElements(
                [value[i]],
                characterNames: characterNames,
                locationNames: locationNames,
              )
            : value[i].text,
      );
    }
    if (findDocument.text != buffer.toString()) {
      findDocument.text = buffer.toString();
    }
  }

  TextSelection selectionForFind(TextRange range) {
    int project(int offset, bool end) {
      if (value.isEmpty) {
        return 0;
      }
      var index = 0;
      while (index + 1 < _findStarts.length &&
          _findStarts[index + 1] <= offset) {
        index++;
      }
      return startOf(index) +
          (value[index].isObject
              ? (end ? 1 : 0)
              : (offset - _findStarts[index]).clamp(
                  0,
                  value[index].text.length,
                ));
    }

    return TextSelection(
      baseOffset: project(range.start, false),
      extentOffset: project(range.end, true),
    );
  }

  Future<void> replaceFindRanges(
    List<TextRange> ranges,
    String replacement,
  ) async {
    if (isComposing || _disposed) {
      return;
    }
    final selected = ranges.map(selectionForFind).toList();
    var skipped = 0;
    _finalize();
    _batchDepth++;
    try {
      for (final range in selected.reversed) {
        final start = positionAt(range.start).index;
        final end = positionAt(range.end).index;
        if (value.sublist(start, end + 1).any((e) => e.isObject)) {
          skipped++;
          continue;
        }
        await replaceRange(range.start, range.end, replacement);
      }
    } finally {
      _batchDepth--;
      _finalize();
    }
    if (skipped > 0) {
      onFindSkipped?.call(skipped);
    }
  }

  final Map<Object, String> _savedIds = {};
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  late List<ScreenplayElement> _committed;
  List<ScreenplayElement>? _indexedValue;
  List<int> _starts = [];
  String _source = '';
  _Snapshot? _transaction;
  bool _finalizeScheduled = false;
  int _batchDepth = 0;
  bool _syncing = false;
  bool _disposed = false;
  bool isComposing = false;
  bool _nativeEdit = false;
  TextSelection? _nativeBefore;
  TextSelection? _nativeAfter;
  String? _nativeReplacement;
  int? _nativeIndex;
  int? _mergeIndex;
  DateTime? _lastEdit;
  int revision = 0;
  Map<String, String> characterNames = {};
  late void Function(List<ScreenplayElement>) onEdited;
  late Future<bool> Function() confirmDelete;
  VoidCallback? onSelectionRequested;

  bool get canUndo => _undo.isNotEmpty || _transaction != null;
  bool get canRedo => _redo.isNotEmpty;
  TextSelection get selection => document.selection;
  String textOf(ScreenplayElement element) =>
      element.isObject ? screenplayCharacterObject : element.text;
  String get source {
    _index();
    return _source;
  }

  void _index() {
    if (identical(_indexedValue, value)) {
      return;
    }
    _indexedValue = value;
    _starts = [];
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0) {
        buffer.write(screenplayElementSeparator);
      }
      _starts.add(buffer.length);
      buffer.write(textOf(value[i]));
    }
    _source = buffer.toString();
    _starts.add(_source.length);
  }

  int startOf(int index) {
    _index();
    return _starts[index.clamp(0, value.length)];
  }

  ({int index, int offset}) positionAt(int offset) {
    if (value.isEmpty) {
      return (index: 0, offset: 0);
    }
    _index();
    var low = 0;
    var high = value.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return (
      index: low,
      offset: (offset - _starts[low]).clamp(0, textOf(value[low]).length),
    );
  }

  bool get crossesElements =>
      value.isNotEmpty &&
      selection.isValid &&
      positionAt(selection.start).index != positionAt(selection.end).index;

  void select(TextSelection next, {bool requestFocus = true}) {
    if (isComposing || _disposed) {
      return;
    }
    _publish(next);
    if (requestFocus) {
      onSelectionRequested?.call();
    }
  }

  void observeInput(
    int index,
    TextEditingValue next,
    TextEditingValue previous,
  ) {
    if (_syncing || _disposed || index >= value.length) {
      return;
    }
    final composingBefore = isComposing;
    isComposing = next.isComposingRangeValid;
    if (next.text != previous.text) {
      _nativeEdit = true;
      _nativeIndex = index;
      _nativeBefore = TextSelection(
        baseOffset:
            startOf(index) +
            previous.selection.baseOffset.clamp(0, previous.text.length),
        extentOffset:
            startOf(index) +
            previous.selection.extentOffset.clamp(0, previous.text.length),
      );
      final local = previous.selection;
      if (local.isValid) {
        final prefix = previous.text.substring(0, local.start);
        final suffix = previous.text.substring(local.end);
        if (next.text.startsWith(prefix) &&
            next.text.endsWith(suffix) &&
            next.text.length >= prefix.length + suffix.length) {
          _nativeReplacement = next.text.substring(
            prefix.length,
            next.text.length - suffix.length,
          );
        }
      }
    }
    if (!(crossesElements && _nativeEdit)) {
      final start = startOf(index);
      final selectionAfter = TextSelection(
        baseOffset:
            start + next.selection.baseOffset.clamp(0, next.text.length),
        extentOffset:
            start + next.selection.extentOffset.clamp(0, next.text.length),
      );
      if (_nativeEdit) {
        _nativeAfter = selectionAfter;
      }
      _publish(selectionAfter);
    }
    if (composingBefore && !isComposing) {
      _scheduleFinalize();
      onEdited(_canonical(value));
    }
  }

  void edit(List<ScreenplayElement> next, {TextSelection? selectionAfter}) {
    if (_disposed) {
      return;
    }
    if (_nativeEdit &&
        crossesElements &&
        _nativeIndex != null &&
        _nativeIndex! < next.length &&
        _nativeIndex! < value.length) {
      final inserted =
          _nativeReplacement ??
          _diff(value[_nativeIndex!].text, next[_nativeIndex!].text).inserted;
      _nativeBefore = selection;
      _nativeAfter = null;
      _nativeEdit = false;
      _nativeIndex = null;
      _nativeReplacement = null;
      unawaited(replaceSelection(inserted));
      return;
    }
    if (splitNativeNewlines &&
        _nativeEdit &&
        !isComposing &&
        _nativeReplacement == '\n') {
      final before = _nativeBefore;
      _nativeEdit = false;
      _nativeIndex = null;
      _nativeBefore = null;
      _nativeAfter = null;
      _nativeReplacement = null;
      if (before != null) {
        _publish(before);
      }
      unawaited(enter(soft: false));
      return;
    }
    final previousDocument = screenplay;
    if (previousDocument != null) {
      if (_nextDocument == null) {
        String? sceneId;
        next = [for (final element in next) element];
        Set<String>? reserved;
        for (var index = 0; index < next.length; index++) {
          final element = next[index];
          if (element.isHeading) {
            sceneId = element.sceneId;
          }
          if (element.id == null) {
            reserved ??= {
              ...previousDocument.reservedIds,
              ...value.map((e) => e.id).whereType<String>(),
              ...next.map((e) => e.id).whereType<String>(),
            };
            final canonical = element.copyWith(
              id: allocateScreenplayDraftId(
                ShortEntityIdType.screenplayElement,
                reserved,
              ),
              episodeId: previousDocument.episodeId,
              sceneId: element.sceneId ?? sceneId,
            );
            next[index] = keys.preserveKey(element, canonical);
          }
        }
        _nextDocument = previousDocument.withBodyEdits(next);
      }
      next = _nextDocument!.elements;
    }
    final docChanged =
        _nextDocument != null &&
        (previousDocument == null ||
            !const SetEquality<String>().equals(
              previousDocument.scenes.keys.toSet(),
              _nextDocument!.scenes.keys.toSet(),
            ) ||
            previousDocument.scenes.entries.any(
              (e) => !e.value.sameAs(_nextDocument!.scenes[e.key]),
            ) ||
            !const MapEquality<String, String?>().equals(
              previousDocument.evidence,
              _nextDocument!.evidence,
            ) ||
            !const MapEquality<String, String>().equals(
              previousDocument.evidenceVersions,
              _nextDocument!.evidenceVersions,
            ));
    if (_same(_committed, next) && !docChanged) {
      _nativeEdit = false;
      _nativeIndex = null;
      _nativeBefore = null;
      _nativeAfter = null;
      _nativeReplacement = null;
      _nextDocument = null;
      return;
    }
    _transaction ??= _Snapshot(
      [..._committed],
      _nativeBefore ?? selection,
      screenplay,
    );
    screenplay = _nextDocument ?? screenplay;
    _nextDocument = null;
    final typedIndex = _nativeEdit ? _nativeIndex : null;
    final structural =
        next.length != _committed.length ||
        docChanged ||
        List.generate(next.length, (i) => i).any(
          (i) =>
              next[i].type != _committed[i].type ||
              keys.keyFor(next[i]) != keys.keyFor(_committed[i]),
        );
    if (structural ||
        typedIndex == null ||
        _mergeIndex != typedIndex ||
        _lastEdit == null ||
        DateTime.now().difference(_lastEdit!) >
            const Duration(milliseconds: 750)) {
      _mergeIndex = null;
    }
    _transaction!.mergeWithPrevious =
        !structural && typedIndex != null && _mergeIndex == typedIndex;
    _transaction!.typedIndex = structural ? null : typedIndex;
    _nativeEdit = false;
    _nativeIndex = null;
    _nativeBefore = null;
    _nativeReplacement = null;
    _committed = [...next];
    revision++;
    super.value = [...next];
    _publish(selectionAfter ?? _nativeAfter ?? selection);
    _nativeAfter = null;
    _redo.clear();
    if (!isComposing) {
      _scheduleFinalize();
      onEdited(_canonical(next));
    }
  }

  void editDocument(ScreenplayDocument next, {TextSelection? selectionAfter}) {
    if (isComposing || _disposed) {
      return;
    }
    _finalize();
    if (selectionAfter == null && value.isNotEmpty) {
      int mapOffset(int offset) {
        final old = positionAt(offset);
        final id = value[old.index].id;
        var start = 0;
        for (final node in next.elements) {
          if (node.id == id) {
            return start + old.offset.clamp(0, textOf(node).length);
          }
          start += textOf(node).length + 1;
        }
        return offset.clamp(0, start == 0 ? 0 : start - 1);
      }

      selectionAfter = TextSelection(
        baseOffset: mapOffset(selection.baseOffset),
        extentOffset: mapOffset(selection.extentOffset),
      );
    }
    _nextDocument = next;
    edit(next.elements, selectionAfter: selectionAfter);
    _finalize();
  }

  void acceptExternalDocument(ScreenplayDocument incoming) {
    final before = screenplay;
    final metadataChanged =
        before != null &&
        (!const SetEquality<String>().equals(
              before.scenes.keys.toSet(),
              incoming.scenes.keys.toSet(),
            ) ||
            before.scenes.entries.any(
              (e) => !e.value.sameAs(incoming.scenes[e.key]),
            ) ||
            !const MapEquality<String, String?>().equals(
              before.evidence,
              incoming.evidence,
            ) ||
            !const MapEquality<String, String>().equals(
              before.evidenceVersions,
              incoming.evidenceVersions,
            ));
    final changed = !_same(_committed, incoming.elements) || metadataChanged;
    final hadHistory =
        _undo.isNotEmpty || _redo.isNotEmpty || _transaction != null;
    final oldSelection = selection;
    final base = value.isEmpty ? null : positionAt(oldSelection.baseOffset);
    final extent = value.isEmpty ? null : positionAt(oldSelection.extentOffset);
    final baseId = base == null ? null : value[base.index].id;
    final extentId = extent == null ? null : value[extent.index].id;
    screenplay = incoming;
    acceptExternal(incoming.elements);
    if (changed) {
      _finalize();
      _undo.clear();
      _redo.clear();
      _mergeIndex = null;
      int restore(String? id, int? offset, int fallback) {
        final index = value.indexWhere((e) => e.id == id);
        return index < 0
            ? fallback.clamp(0, source.length)
            : startOf(index) +
                  (offset ?? 0).clamp(0, textOf(value[index]).length);
      }

      _publish(
        TextSelection(
          baseOffset: restore(baseId, base?.offset, oldSelection.baseOffset),
          extentOffset: restore(
            extentId,
            extent?.offset,
            oldSelection.extentOffset,
          ),
        ),
      );
      if (hadHistory) {
        onHistoryInvalid?.call();
      }
    }
  }

  Future<void> splitScene() async {
    final current = screenplay;
    if (current == null || isComposing || _disposed) {
      return;
    }
    if (current.elements.isEmpty) {
      editDocument(current.createFirstScene());
      return;
    }
    final position = positionAt(selection.extentOffset);
    final node = value[position.index];
    if (node.isHeading) {
      final scene = current.sceneElements(node.sceneId!);
      if (scene.length == 1) {
        final body = ScreenplayElement(
          id: allocateScreenplayDraftId(ShortEntityIdType.screenplayElement, {
            ...current.reservedIds,
          }),
          sceneId: node.sceneId,
          episodeId: node.episodeId,
          type: ScreenplayElementType.action,
        );
        final nodes = [...value]..insert(position.index + 1, body);
        final next = current
            .withBodyEdits(nodes)
            .split(ScreenplayPosition(body.id!, 0));
        editDocument(next);
        return;
      }
      editDocument(current.split(ScreenplayPosition(scene[1].id!, 0)));
      return;
    }
    final next = current.split(ScreenplayPosition(node.id!, position.offset));
    editDocument(next);
  }

  Future<void> removeSceneHeading(String sceneId) async {
    final current = screenplay;
    if (current == null || isComposing || _disposed) {
      return;
    }
    final beforeRevision = revision;
    try {
      final next = current.merge(sceneId);
      if (await confirmStructure!(current, next, false) &&
          !_disposed &&
          revision == beforeRevision) {
        editDocument(next);
      }
    } on ScreenplayServiceException catch (error) {
      if (onCommandError == null) {
        rethrow;
      }
      onCommandError!(error.errorCode);
    }
  }

  /// 删掉只剩一条空行的场次。场是空的，不走 [merge]：并场会把本场出场人物
  /// 带进上一场，确认框也会列出一串空场用不上的结构影响。
  Future<void> deleteEmptyScene(String sceneId) async {
    final current = screenplay;
    // 单场视图里文档只有这一场，删了编辑器就空了，交给场次列表删。
    if (current == null || !current.fullEpisode || isComposing || _disposed) {
      return;
    }
    final beforeRevision = revision;
    final heading = value.indexWhere(
      (e) => e.isHeading && e.sceneId == sceneId,
    );
    final next = current.deleteScenes({sceneId});
    if (!await confirmDeleteScene!(current, next, sceneId) ||
        _disposed ||
        revision != beforeRevision) {
      return;
    }
    final caret = heading <= 0 ? 0 : startOf(heading) - 1;
    editDocument(next, selectionAfter: TextSelection.collapsed(offset: caret));
    select(TextSelection.collapsed(offset: caret));
  }

  void acceptExternal(List<ScreenplayElement> incoming) {
    if (!_same(_committed, incoming)) {
      revision++;
      _finalize();
      _undo.clear();
      _redo.clear();
      _mergeIndex = null;
    }
    _committed = [...incoming];
    super.value = [...incoming];
    _publish(selection);
  }

  void acceptSave(
    List<ScreenplayElement> snapshot,
    List<ScreenplayElement> saved,
  ) {
    keys.acceptSave(snapshot, saved);
    for (var i = 0; i < snapshot.length; i++) {
      _savedIds[keys.keyFor(snapshot[i])] = saved[i].id!;
    }
  }

  /// 保存成功后同步当前编辑与撤销历史中的最终身份。
  /// 同号确认仍清除新建标记，但复用 value，不再像旧实现一样通知监听器；
  /// 当前节点刷新不依赖这些标记，监听器也不应把此通知当作保存完成事件。
  void acknowledgeDocumentIds(
    Map<String, String> sceneIds,
    Map<String, String> elementIds,
  ) {
    if (sceneIds.isEmpty && elementIds.isEmpty) {
      return;
    }
    List<ScreenplayElement> remap(List<ScreenplayElement> values) {
      List<ScreenplayElement>? mapped;
      for (final (index, element) in values.indexed) {
        final id = elementIds[element.id] ?? element.id;
        final sceneId = sceneIds[element.sceneId] ?? element.sceneId;
        if (id != element.id || sceneId != element.sceneId) {
          mapped ??= [...values];
          mapped[index] = element.copyWith(id: id, sceneId: sceneId);
        }
      }
      if (mapped == null) {
        // 同号 acceptSave 只会写回 keyFor 已有的映射或默认 ID，可省略。
        return values;
      }
      keys.acceptSave(values, mapped);
      return mapped;
    }

    screenplay = screenplay?.remapIdentities(sceneIds, elementIds);
    _nextDocument = _nextDocument?.remapIdentities(sceneIds, elementIds);
    _committed = remap(_committed);
    for (final snapshot in [..._undo, ..._redo, ?_transaction]) {
      snapshot.screenplay = snapshot.screenplay?.remapIdentities(
        sceneIds,
        elementIds,
      );
      snapshot.elements = remap(snapshot.elements);
    }
    super.value = remap(value);
    _publish(selection);
  }

  List<ScreenplayElement> _canonical(List<ScreenplayElement> elements) => [
    for (final element in elements)
      if (_savedIds[keys.keyFor(element)] case final String id)
        element.copyWith(id: id)
      else
        element,
  ];

  void _scheduleFinalize() {
    if (_finalizeScheduled) {
      return;
    }
    _finalizeScheduled = true;
    scheduleMicrotask(() {
      _finalizeScheduled = false;
      if (!_disposed && !isComposing && _batchDepth == 0) {
        _finalize();
      }
    });
  }

  void _finalize() {
    final transaction = _transaction;
    _transaction = null;
    if (transaction == null) {
      return;
    }
    if (!transaction.mergeWithPrevious || _undo.isEmpty) {
      _undo.add(transaction);
      if (_undo.length > 200) {
        _undo.removeAt(0);
      }
    }
    _mergeIndex = transaction.typedIndex;
    _lastEdit = DateTime.now();
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);
  void _restore(List<_Snapshot> from, List<_Snapshot> to) {
    if (isComposing || _disposed) {
      return;
    }
    _finalize();
    if (from.isEmpty) {
      return;
    }
    to.add(_Snapshot([...value], selection, screenplay));
    final snapshot = from.removeLast();
    // 已知边界（2026-09-17 决定暂不处理）：reservedIds 也随快照回退。
    // 已保存场次撤销后、撤销尚未落库时，新候选可能碰巧复用该场次 ID；
    // 后续换号可能遗漏旧场次删除，详见 ScreenplayService.applyDocument。
    screenplay = snapshot.screenplay;
    _committed = _canonical(snapshot.elements);
    revision++;
    super.value = [..._committed];
    _mergeIndex = null;
    _publish(snapshot.selection);
    onEdited([..._committed]);
    onSelectionRequested?.call();
  }

  String selectedText() {
    if (!selection.isValid || selection.isCollapsed) {
      return '';
    }
    return textInRange(selection.start, selection.end);
  }

  String textInRange(int start, int end) {
    var text = source.substring(start, end);
    for (var i = value.length - 1; i >= 0; i--) {
      final offset = startOf(i);
      if (value[i].isObject && offset >= start && offset < end) {
        final relative = offset - start;
        text = text.replaceRange(
          relative,
          relative + 1,
          value[i].isHeading
              ? renderScreenplayElements(
                  [value[i]],
                  characterNames: characterNames,
                  locationNames: locationNames,
                )
              : '${characterNames[value[i].characterId] ?? ''}：',
        );
      }
    }
    return text.replaceAll(screenplayElementSeparator, '\n');
  }

  Future<void> replaceSelection(String replacement) =>
      replaceRange(selection.start, selection.end, replacement);

  Future<void> enter({required bool soft}) async {
    if (isComposing || _disposed) {
      return;
    }
    if (soft) {
      await replaceSelection('\n');
      return;
    }
    _batchDepth++;
    try {
      if (!selection.isCollapsed) {
        await replaceSelection('');
        if (!selection.isCollapsed || _disposed) {
          return;
        }
      }
      if (screenplay != null &&
          (value.isEmpty ||
              value[positionAt(selection.extentOffset).index].isHeading)) {
        if (value.isEmpty) {
          editDocument(screenplay!.createFirstScene());
        } else {
          final at = positionAt(selection.extentOffset).index;
          final heading = value[at];
          if (at + 1 < value.length && !value[at + 1].isHeading) {
            select(TextSelection.collapsed(offset: startOf(at + 1)));
          } else {
            final node = ScreenplayElement(
              id: allocateScreenplayDraftId(
                ShortEntityIdType.screenplayElement,
                {...screenplay!.reservedIds},
              ),
              episodeId: heading.episodeId,
              sceneId: heading.sceneId,
              type: ScreenplayElementType.action,
            );
            edit([...value]..insert(at + 1, node));
            select(TextSelection.collapsed(offset: startOf(at + 1)));
          }
        }
      } else if (value.isEmpty) {
        edit([
          ScreenplayElement(type: ScreenplayElementType.action),
        ], selectionAfter: const TextSelection.collapsed(offset: 0));
      } else {
        final position = positionAt(selection.extentOffset);
        final current = value[position.index];
        if (current.type == ScreenplayElementType.character) {
          final result = prepareScreenplayDialogue(value, position.index);
          edit(result.elements);
          select(TextSelection.collapsed(offset: startOf(result.index)));
        } else {
          final before = current.text.substring(0, position.offset);
          final after = current.text.substring(position.offset);
          final next = [...value]
            ..[position.index] = keys.preserveKey(
              current,
              current.copyWith(text: before),
            );
          next.insert(
            position.index + 1,
            ScreenplayElement(
              type: screenplayNextElementType(current.type),
              text: after,
            ),
          );
          edit(
            next,
            selectionAfter: TextSelection.collapsed(
              offset: startOf(position.index) + before.length + 1,
            ),
          );
        }
      }
      onSelectionRequested?.call();
    } finally {
      _batchDepth--;
      _scheduleFinalize();
    }
  }

  Future<void> replaceRange(
    int start,
    int end,
    String replacement, {
    Future<void> Function(String text)? beforeReplace,
  }) async {
    try {
      await _replaceRange(
        start,
        end,
        replacement,
        beforeReplace: beforeReplace,
      );
    } on ScreenplayServiceException catch (error) {
      if (onCommandError == null) {
        rethrow;
      }
      onCommandError!(error.errorCode);
    }
  }

  Future<void> _replaceRange(
    int start,
    int end,
    String replacement, {
    Future<void> Function(String text)? beforeReplace,
  }) async {
    if (isComposing || _disposed) {
      return;
    }
    start = start.clamp(0, source.length);
    end = end.clamp(start, source.length);
    replacement = replacement
        .replaceAll(screenplayElementSeparator, '\n')
        .replaceAll(screenplayCharacterObject, '');
    if (start == end && replacement.isEmpty) {
      return;
    }
    if (screenplay != null && value.isNotEmpty) {
      final origin = positionAt(start);
      if (value[origin.index].isHeading) {
        if (start == end) {
          await enter(soft: false);
          if (replacement.isNotEmpty) {
            await replaceSelection(replacement);
          }
          return;
        }
        if (origin.offset == 1 && end == start + 1 && replacement.isEmpty) {
          await removeSceneHeading(value[origin.index].sceneId!);
          return;
        }
      }
    }
    if (value.isNotEmpty) {
      final origin = positionAt(start);
      if (value[origin.index].type == ScreenplayElementType.character) {
        if (start == end) {
          final dialogue = prepareScreenplayDialogue(value, origin.index);
          final target = dialogue.elements[dialogue.index];
          final next = [...dialogue.elements]
            ..[dialogue.index] = keys.preserveKey(
              target,
              target.copyWith(text: '$replacement${target.text}'),
            );
          edit(next);
          select(
            TextSelection.collapsed(
              offset: startOf(dialogue.index) + replacement.length,
            ),
          );
          return;
        }
        if (origin.offset == 1 && origin.index + 1 < value.length) {
          start = startOf(origin.index + 1);
          if (start == end && replacement.isEmpty) {
            return;
          }
        }
      }
    }
    var extendedEnd = end;
    for (var i = 0; i < value.length; i++) {
      if (!value[i].isObject || start > startOf(i) || end <= startOf(i)) {
        continue;
      }
      var last = i;
      while (last + 1 < value.length &&
          (value[last + 1].type == ScreenplayElementType.dialogue ||
              value[last + 1].type == ScreenplayElementType.parenthetical)) {
        last++;
      }
      if (last > i) {
        final blockEnd = startOf(last) + textOf(value[last]).length;
        if (blockEnd > extendedEnd) {
          extendedEnd = blockEnd;
        }
      }
    }
    final currentDocument = screenplay;
    if (currentDocument != null && value.isEmpty) {
      if (replacement.isNotEmpty) {
        editDocument(currentDocument.createFirstScene(text: replacement));
      }
      return;
    }
    final selectsHeading =
        currentDocument != null &&
        value.asMap().entries.any(
          (entry) =>
              entry.value.isHeading &&
              start <= startOf(entry.key) &&
              extendedEnd > startOf(entry.key),
        );
    if (selectsHeading) {
      final first = positionAt(start);
      final last = positionAt(extendedEnd);
      final planned = currentDocument.replaceRange(
        ScreenplayPosition(value[first.index].id!, first.offset),
        ScreenplayPosition(value[last.index].id!, last.offset),
        replacement,
      );
      final beforeRevision = revision;
      if (!await confirmStructure!(
            currentDocument,
            planned,
            extendedEnd > end,
          ) ||
          _disposed ||
          beforeRevision != revision) {
        return;
      }
      if (beforeReplace != null) {
        await beforeReplace(textInRange(start, extendedEnd));
      }
      if (_disposed || beforeRevision != revision) {
        return;
      }
      editDocument(
        planned,
        selectionAfter: TextSelection.collapsed(
          offset: start + replacement.length,
        ),
      );
      onSelectionRequested?.call();
      return;
    }
    if (extendedEnd > end) {
      final beforeRevision = revision;
      if (!await confirmDelete() || _disposed || beforeRevision != revision) {
        _publish(selection);
        onSelectionRequested?.call();
        return;
      }
      end = extendedEnd;
    }
    if (beforeReplace != null) {
      final beforeRevision = revision;
      final beforeSelection = selection;
      await beforeReplace(textInRange(start, end));
      if (_disposed ||
          revision != beforeRevision ||
          selection != beforeSelection) {
        return;
      }
    }
    if (value.isEmpty) {
      if (replacement.isNotEmpty) {
        edit([
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: replacement,
          ),
        ], selectionAfter: TextSelection.collapsed(offset: replacement.length));
      }
      onSelectionRequested?.call();
      return;
    }
    final first = positionAt(start);
    final last = positionAt(end);
    final left = value[first.index];
    final right = value[last.index];
    final keepRightCharacter =
        right.type == ScreenplayElementType.character && last.offset == 0;
    final prefix = left.type == ScreenplayElementType.character
        ? ''
        : left.text.substring(0, first.offset);
    final suffix = right.type == ScreenplayElementType.character
        ? ''
        : right.text.substring(last.offset);
    final next = [...value.take(first.index)];
    final keepLeft =
        left.type != ScreenplayElementType.character &&
        (first.index == last.index ||
            prefix.isNotEmpty ||
            replacement.isNotEmpty);
    if (keepLeft) {
      final joined = first.index == last.index || left.type == right.type;
      next.add(
        keys.preserveKey(
          left,
          left.copyWith(text: '$prefix$replacement${joined ? suffix : ''}'),
        ),
      );
      if (!joined && suffix.isNotEmpty) {
        next.add(keys.preserveKey(right, right.copyWith(text: suffix)));
      }
    } else if (replacement.isNotEmpty) {
      next.add(
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: replacement,
        ),
      );
      if (suffix.isNotEmpty) {
        next.add(keys.preserveKey(right, right.copyWith(text: suffix)));
      }
    } else if (suffix.isNotEmpty) {
      next.add(keys.preserveKey(right, right.copyWith(text: suffix)));
    }
    if (keepRightCharacter) {
      next.add(right);
    }
    next.addAll(value.skip(last.index + 1));
    edit(
      next,
      selectionAfter: TextSelection.collapsed(
        offset: start + replacement.length,
      ),
    );
    onSelectionRequested?.call();
  }

  void _documentChanged() {
    if (_syncing || _disposed) {
      return;
    }
    if (document.text == source) {
      return;
    }
    final updated = document.value;
    final parts = updated.text.split(screenplayElementSeparator);
    if (parts.length == value.length &&
        List.generate(value.length, (i) => i).every(
          (i) => !value[i].isObject || parts[i] == screenplayCharacterObject,
        )) {
      edit([
        for (var i = 0; i < value.length; i++)
          if (value[i].isObject)
            value[i]
          else
            keys.preserveKey(value[i], value[i].copyWith(text: parts[i])),
      ], selectionAfter: updated.selection);
    } else {
      final change = _diff(source, updated.text);
      _publish(selection);
      unawaited(replaceRange(change.start, change.end, change.inserted));
    }
  }

  void _publish(TextSelection next) {
    _syncing = true;
    final text = source;
    document.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: next.baseOffset.clamp(0, text.length),
        extentOffset: next.extentOffset.clamp(0, text.length),
        affinity: next.affinity,
      ),
    );
    _syncing = false;
    refreshFindProjection();
  }

  bool _same(List<ScreenplayElement> a, List<ScreenplayElement> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => i).every(
        (i) =>
            (screenplay == null || a[i].id == b[i].id) &&
            a[i].sceneId == b[i].sceneId &&
            a[i].interiorExterior == b[i].interiorExterior &&
            a[i].locationId == b[i].locationId &&
            a[i].timeLabel == b[i].timeLabel &&
            a[i].type == b[i].type &&
            a[i].text == b[i].text &&
            a[i].characterId == b[i].characterId &&
            a[i].extension == b[i].extension,
      );

  @override
  void dispose() {
    _disposed = true;
    document.removeListener(_documentChanged);
    document.dispose();
    findDocument.dispose();
    super.dispose();
  }
}

class _Snapshot {
  _Snapshot(this.elements, this.selection, [this.screenplay]);
  ScreenplayDocument? screenplay;
  List<ScreenplayElement> elements;
  final TextSelection selection;
  bool mergeWithPrevious = false;
  int? typedIndex;
}

({int start, int end, String inserted}) _diff(String before, String after) {
  var start = 0;
  while (start < before.length &&
      start < after.length &&
      before.codeUnitAt(start) == after.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = before.length;
  var newEnd = after.length;
  while (oldEnd > start &&
      newEnd > start &&
      before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return (start: start, end: oldEnd, inserted: after.substring(start, newEnd));
}
