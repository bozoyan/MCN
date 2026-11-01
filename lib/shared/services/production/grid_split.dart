// 职责: 在后台 isolate 中按取整边界等分图片，逐格写入临时 PNG。
// 关联文件:
//   lib/shared/services/production/grid_orchestrator.dart
//   lib/shared/models/production/group_layout.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'ffmpeg_runner.dart';
import '../../models/production/media.dart';
import 'package:image/image.dart' as image;

class GridCrop {
  const GridCrop({
    required this.path,
    required this.index,
    required this.row,
    required this.col,
    required this.width,
    required this.height,
  });
  final String path;
  final int index, row, col, width, height;
}

typedef GridCellRect = ({int x, int y, int width, int height});

List<GridCellRect> gridCellRects(int width, int height, int rows, int cols) {
  if (rows < 1 ||
      cols < 1 ||
      rows > 5 ||
      cols > 5 ||
      rows * cols <= 1 ||
      width < cols ||
      height < rows) {
    throw const FormatException('Invalid grid dimensions');
  }
  return [
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < cols; col++)
        (
          x: (col * width / cols).round(),
          y: (row * height / rows).round(),
          width:
              ((col + 1) * width / cols).round() - (col * width / cols).round(),
          height:
              ((row + 1) * height / rows).round() -
              (row * height / rows).round(),
        ),
  ];
}

Future<List<GridCrop>> splitProductionGrid({
  required String sourcePath,
  required String directory,
  required int rows,
  required int cols,
  Set<int> selected = const {},
  MediaCancellation? cancellation,
}) async {
  if (cancellation?.cancelled == true) {
    throw const MediaException(MediaFailure.cancelled);
  }
  final control = ReceivePort();
  final subscription = control.listen((message) {
    final port = message as SendPort;
    unawaited(
      cancellation?.bind(() async {
        port.send(null);
      }),
    );
  });
  try {
    return await _runGridSplit((
      path: sourcePath,
      directory: directory,
      rows: rows,
      cols: cols,
      selected: selected,
      control: control.sendPort,
    ));
  } finally {
    cancellation?.unbind();
    await subscription.cancel();
    control.close();
  }
}

typedef _GridSplitInput = ({
  String path,
  String directory,
  int rows,
  int cols,
  Set<int> selected,
  SendPort control,
});
Future<List<GridCrop>> _runGridSplit(_GridSplitInput input) =>
    Isolate.run(() => _splitGrid(input));
Future<List<GridCrop>> _splitGrid(_GridSplitInput input) async {
  final commands = ReceivePort();
  var cancelled = false;
  final subscription = commands.listen((_) {
    cancelled = true;
  });
  input.control.send(commands.sendPort);
  final directory = input.directory;
  final rows = input.rows;
  final cols = input.cols;
  final selected = input.selected;
  try {
    final sourcePath = input.path;
    final decoded = image.decodeImage(await File(sourcePath).readAsBytes());
    if (decoded == null) {
      throw const FormatException('Unsupported image');
    }
    final source = image.bakeOrientation(decoded);
    final rects = gridCellRects(source.width, source.height, rows, cols);
    if (selected.any((slot) => slot < 0 || slot >= rects.length)) {
      throw const FormatException('Invalid selected cell');
    }
    final result = <GridCrop>[];
    for (var index = 0; index < rects.length; index++) {
      if (cancelled) {
        throw const MediaException(MediaFailure.cancelled);
      }
      if (selected.isNotEmpty && !selected.contains(index)) {
        continue;
      }
      final rect = rects[index];
      final crop = image.copyCrop(
        source,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
      );
      final path = '$directory/$index.png';
      await File(path).writeAsBytes(image.encodePng(crop));
      result.add(
        GridCrop(
          path: path,
          index: index,
          row: index ~/ cols,
          col: index % cols,
          width: rect.width,
          height: rect.height,
        ),
      );
    }
    return result;
  } finally {
    await subscription.cancel();
    commands.close();
  }
}
