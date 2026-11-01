// 职责: 地图 Agent 交互契约 — 定义交接指令、制图草稿与打开聊天的瞬态请求。
// 关联文件:
//   lib/shared/providers/map_agent_providers.dart
//   lib/shared/services/ai/tools_run.dart
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/mobile/features/map/studio_page.dart
import '../database/novel_content_database.dart' show mapTypeRegion;

const mapAgentHandoffPrompt = '''
请为引用的地点设计一张地图。先使用 Read 读取引用资源，再根据本次任务与可用技能的描述，匹配并通过 AgentSkill 加载适用的地图设计类技能，完成地点建模、校验后，按 Run help map 的说明提交制图草案。
''';

/// [subMapScale] 非空表示目标是子地点的地图（如「城镇平面图」），
/// 需要提示 Agent 只规划该地点的子树、按对应尺度设计。
/// 交给 Agent 的子地图尺度描述，与 buildMapImagePrompt 的尺度措辞对齐。
String mapAgentSubMapScale(String mapType) =>
    mapType == mapTypeRegion ? '区域地图' : '城镇平面图';

String buildMapAgentHandoffPrompt({
  required String? styleId,
  required String? styleWord,
  String? subMapScale,
}) {
  final base = subMapScale == null
      ? mapAgentHandoffPrompt
      : '''$mapAgentHandoffPrompt
这是子地点的地图，按$subMapScale的尺度设计：只规划引用地点的子孙地点，不要新增或改动它之外的地点。''';
  final normalizedStyle = styleWord?.trim();
  if (normalizedStyle == null || normalizedStyle.isEmpty) {
    return base;
  }
  final styleSource = styleId == mapCustomStyleId ? '自定义风格' : '风格选项 $styleId';
  return '''$base
当前画风：$normalizedStyle（$styleSource）。请在提交制图草案时保留为独立风格参数，不要写入地图内容提示词。''';
}

const mapDesignStyleIds = <String>{
  'parchment',
  'inkmap',
  'engraving',
  'realistic',
  'woodcut',
  'watercolor',
  'atlas',
  'custom',
};
const mapDesignResolutionIds = <String>{'1k', '2k', '4k'};
const mapDesignQualityIds = <String>{'low', 'medium', 'high'};
const mapDesignDefaultStyleId = 'parchment';
const mapCustomStyleId = 'custom';
const mapDesignDefaultResolutionId = '2k';
const mapDesignDefaultQualityId = 'medium';

/// Agent 交给制图师审阅的生成参数；提交草稿本身不会生成或采用图片。
class MapDesignDraft {
  const MapDesignDraft({
    required this.worldId,
    required this.prompt,
    this.styleId = mapDesignDefaultStyleId,
    this.customStyleWord,
    this.resolutionId = mapDesignDefaultResolutionId,
    this.qualityId = mapDesignDefaultQualityId,
    this.includeLocations = true,
    this.referenceCurrentImage = false,
  });

  final String worldId;

  /// 地图内容提示词，不含画风；画风由 [styleId] 独立提交。
  final String prompt;
  final String styleId;

  /// [styleId] 为 [mapCustomStyleId] 时的自定义画风文字。
  final String? customStyleWord;
  final String resolutionId;
  final String qualityId;
  final bool includeLocations;
  final bool referenceCurrentImage;
}

class MapDesignDraftKey {
  const MapDesignDraftKey({required this.databasePath, required this.worldId});

  final String databasePath;
  final String worldId;

  @override
  bool operator ==(Object other) {
    return other is MapDesignDraftKey &&
        other.databasePath == databasePath &&
        other.worldId == worldId;
  }

  @override
  int get hashCode => Object.hash(databasePath, worldId);
}

/// 地图工作台请求现有聊天面板接手设计时携带的目标。
class MapAgentHandoffRequest {
  const MapAgentHandoffRequest({
    required this.databasePath,
    required this.worldId,
    required this.worldName,
    required this.styleId,
    required this.styleWord,
    this.subMapScale,
  });

  final String databasePath;

  /// 目标地图所属地点：world 本身或它的子地点。
  final String worldId;
  final String worldName;
  final String? styleId;
  final String? styleWord;

  /// 子地点地图的尺度描述；world 地图为 null。
  final String? subMapScale;
}
