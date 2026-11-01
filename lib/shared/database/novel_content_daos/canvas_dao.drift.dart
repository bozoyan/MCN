// dart format width=80
// ignore_for_file: type=lint
part of 'canvas_dao.dart';

mixin _$CanvasDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $CanvasesTable get canvases => attachedDatabase.canvases;
  $CanvasNodesTable get canvasNodes => attachedDatabase.canvasNodes;
  $CanvasEdgesTable get canvasEdges => attachedDatabase.canvasEdges;
  CanvasDaoManager get managers => CanvasDaoManager(this);
}

class CanvasDaoManager {
  final _$CanvasDaoMixin _db;
  CanvasDaoManager(this._db);
  $$CanvasesTableTableManager get canvases =>
      $$CanvasesTableTableManager(_db.attachedDatabase, _db.canvases);
  $$CanvasNodesTableTableManager get canvasNodes =>
      $$CanvasNodesTableTableManager(_db.attachedDatabase, _db.canvasNodes);
  $$CanvasEdgesTableTableManager get canvasEdges =>
      $$CanvasEdgesTableTableManager(_db.attachedDatabase, _db.canvasEdges);
}
