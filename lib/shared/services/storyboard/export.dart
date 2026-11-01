// 职责: 按场序和段序生成可读资源引用与身份清单的 Markdown/CSV 片段表。
// 关联文件:
//   lib/shared/models/storyboard/prompt.dart
//   lib/shared/services/storyboard/service.dart
import '../../database/novel_content_database.dart';
import '../../models/storyboard/prompt.dart';

class StoryboardExportRow {
  const StoryboardExportRow({
    required this.scene,
    required this.number,
    required this.shot,
  });
  final String scene;
  final String number;
  final ProductionClipRow shot;
}

String exportStoryboard(
  List<StoryboardExportRow> rows, {
  required bool csv,
  required List<String> headings,
  required String Function(String) statusLabel,
  Map<String, String>? videoFiles,
}) {
  final data = [
    headings,
    for (final row in rows)
      [
        row.scene,
        row.number,
        row.shot.title,
        StoryboardPrompt.parse(row.shot.prompt).plainText,
        statusLabel(
          row.shot.adoptedAssetId == null ? 'unselected' : 'selected',
        ),
        [
          row.shot.providerId ?? '',
          row.shot.modelId ?? '',
          if (row.shot.kind == 'video') row.shot.referenceMode,
          if (row.shot.durationMs != null) '${row.shot.durationMs! / 1000}s',
          row.shot.ratio,
          row.shot.resolution,
        ].where((s) => s.isNotEmpty).join(' · '),
        StoryboardPrompt.parse(row.shot.prompt).references
            .map((r) => '${r.label} [${r.identity}]')
            .toSet()
            .join('; '),
        if (videoFiles != null) videoFiles[row.shot.id] ?? '',
      ],
  ];
  if (csv) {
    String escape(String value) => '"${value.replaceAll('"', '""')}"';
    return '${data.map((row) => row.map(escape).join(',')).join('\r\n')}\r\n';
  }
  String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('|', '\\|')
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', '<br>');
  String line(List<String> values) => '| ${values.map(escape).join(' | ')} |';
  return '${[line(data.first), line(List.filled(headings.length, '---')), ...data.skip(1).map(line)].join('\n')}\n';
}
