// 职责: 运行时读取外置魔搭 LoRA 清单，把生效 LoRA 的触发词前置到生图提示词。
// 关联文件:
//   lib/shared/services/ai/image/modelscope.dart
//   lib/shared/models/image/extras.dart
//   modelscope_models.json
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/image/extras.dart';

/// 清单里的一条 LoRA/底座条目。
/// [modelId] 对应记录的 Model 字段（LoRA 完整仓库 ID），同时是触发词反查键；
/// [triggerWord] 对应 prompt 字段，生图时前置到用户提示词。
class ModelScopeCatalogEntry {
  const ModelScopeCatalogEntry({
    required this.category,
    required this.modelId,
    required this.baseModel,
    required this.triggerWord,
    this.name = '',
    this.coverUrl = '',
  });

  /// 顶层分组名（如 LORA / EDIT / FEI），供 UI 分组展示。
  final String category;

  /// LoRA 完整仓库 ID，如 bozoyan/Q-YANBO。
  final String modelId;

  /// 底座短名，如 Qwen-Image-2.1-Turbo。
  final String baseModel;

  /// 触发词；为空表示这条没有触发词。
  final String triggerWord;

  /// 显示名。
  final String name;

  /// 封面图 URL（仅展示，接口不消费）。
  final String coverUrl;
}

/// 运行时读取的外置 LoRA 清单。
///
/// 清单文件按约定放在 cwd 或可执行文件同目录，换清单不改代码。
/// 读取失败时退化为空清单，绝不阻塞出图——触发词只是增强项。
class ModelScopeLoraCatalog {
  ModelScopeLoraCatalog(this._entries)
    : _triggerByModel = {
        for (final entry in _entries)
          if (entry.triggerWord.isNotEmpty) entry.modelId: entry.triggerWord,
      };

  static const _catalogFileName = 'modelscope_models.json';

  final List<ModelScopeCatalogEntry> _entries;

  /// LoRA 仓库 ID → 触发词，只读非空触发词。
  final Map<String, String> _triggerByModel;

  /// 进程内缓存：清单变更后需重启应用生效（外置文件按次读取成本高于收益）。
  static ModelScopeLoraCatalog? _cached;

  List<ModelScopeCatalogEntry> get entries => _entries;

  /// 按 LoRA 仓库 ID 反查触发词；无命中返回 null。
  String? triggerFor(String modelId) => _triggerByModel[modelId.trim()];

  /// 解析外置 JSON：遍历顶层所有数组，按 Model 去重。
  factory ModelScopeLoraCatalog.fromJson(Map<String, dynamic> json) {
    final entries = <ModelScopeCatalogEntry>[];
    final seen = <String>{};
    for (final section in json.entries) {
      final value = section.value;
      if (value is! List) {
        continue;
      }
      for (final item in value) {
        if (item is! Map) {
          continue;
        }
        final modelId = item['Model']?.toString().trim() ?? '';
        if (modelId.isEmpty || !seen.add(modelId)) {
          continue;
        }
        entries.add(
          ModelScopeCatalogEntry(
            category: section.key,
            modelId: modelId,
            baseModel: item['Bmodel']?.toString().trim() ?? '',
            triggerWord: item['prompt']?.toString().trim() ?? '',
            name: item['Name']?.toString().trim() ?? '',
            coverUrl: item['Purl']?.toString().trim() ?? '',
          ),
        );
      }
    }
    return ModelScopeLoraCatalog(entries);
  }

  /// 从磁盘读取清单。cwd 优先，回退到可执行文件同目录。
  /// 任一来源读取失败都继续尝试下一个，全部失败返回空清单。
  static Future<ModelScopeLoraCatalog> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final catalog = await _loadFromDisk();
    // 只读成功结果：空清单不缓存，文件后续补齐时下一次仍有机会读到。
    if (catalog._entries.isNotEmpty) {
      _cached = catalog;
    }
    return catalog;
  }

  static Future<ModelScopeLoraCatalog> _loadFromDisk() async {
    final candidates = <String>[
      p.join(Directory.current.path, _catalogFileName),
      p.join(p.dirname(Platform.resolvedExecutable), _catalogFileName),
    ];
    for (final candidate in candidates) {
      try {
        final file = File(candidate);
        if (!await file.exists()) {
          continue;
        }
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        return ModelScopeLoraCatalog.fromJson(decoded);
      } catch (_) {
        // 单个候选损坏不影响下一个；索引失败不记录敏感文件内容。
        continue;
      }
    }
    return ModelScopeLoraCatalog(const []);
  }

  /// 仅测试使用：清空进程内缓存。
  static void resetCacheForTesting() => _cached = null;

  /// 注入式构造，供测试直接喂清单内容而不依赖外置文件。
  factory ModelScopeLoraCatalog.forTesting(
    Iterable<ModelScopeCatalogEntry> entries,
  ) => ModelScopeLoraCatalog(List.unmodifiable(entries));

  /// 把生效 LoRA 的触发词按顺序去重后拼到用户提示词最前面。
  ///
  /// 规则（ModelScope-LoRA清单生图方案说明.md）：
  /// 逐个按 LoRA 的 Model 字段反查触发词，按顺序去重，
  /// 结果形如「触发词1, 触发词2, 用户提示词」；无命中则原样返回。
  String prefixTriggers(String userPrompt, List<ModelScopeLora> loras) {
    if (loras.isEmpty) {
      return userPrompt;
    }
    final triggers = <String>[];
    final seen = <String>{};
    for (final lora in loras) {
      final trigger = triggerFor(lora.repoId);
      if (trigger == null || !seen.add(trigger)) {
        continue;
      }
      triggers.add(trigger);
    }
    if (triggers.isEmpty) {
      return userPrompt;
    }
    return '${triggers.join(', ')}, $userPrompt';
  }
}
