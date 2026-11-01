# AI 批量替换工具 Replace 方案

## 1. 背景

### 现状

- `Edit`（`lib/shared/services/ai/tools_edit.dart`）是唯一的局部文本修改工具：单路径、逐字符精确匹配、默认只允许命中一处，多处命中且 `all != true` 时报 `ambiguous_old_text`。
- `Grep`（`lib/shared/services/ai/tools_grep.dart`）负责跨资源查找，路径收集复用 `_collectResourcePaths` / `_compileResourceGlob` / `_looksLikeResourceFieldPath`（`tools_resource_search_support.dart`），单次返回上限 `_resourceGrepMaxMatches = 32`。
- 每次成功 Edit 通过 `_stageTextChange`（`tools.dart:844`）落一条 working change，用户可逐条 accept / reject。
- `relations` 集合被显式排除在资源树之外（`tools_resource_search_support.dart:81`）；`canvas` 虽在 `_rootCollections`，但 `_buildResourceHandlers()` 未注册 canvas handler，资源树里只有 `/canvas` 一个光杆路径，没有任何子路径。

### 问题

```text
问题：跨资源改同一处模式，成本与失败率都不可接受
- 症状：模型只能 Grep 定位 → 逐条 Read 确认精确文本 → 逐条 Edit。100 章正文 = 上百次工具往返。
- 根因：没有任何工具能一次作用于多个资源字段；Edit 的单点精确匹配语义本身就排斥批量。
- 影响：token 成本随命中数线性放大；中途上下文被压缩会导致漏改；漏改一处即设定崩坏。
```

两个真实场景把问题暴露得最彻底：

**场景一 — 角色改名。** `李明` → `李泽明`，散落在 100+ 章正文、角色资料、大纲。危险点在于 `李明` 是 `李明月`（另一个角色）的前缀。中文没有词边界可用：Dart 的 `\b` 基于 `\w`（`[A-Za-z0-9_]`），汉字两侧永远不构成边界，写了也不生效。要排除误伤只能靠负向断言 `李明(?!月)` —— **字面替换在中文人名上不安全**。

**场景二 — 标点规范化。** 全稿单引号转双引号。`Grep "'"` 会命中几乎每一章，32 条上限当场截断，模型连完整 path 清单都拿不到。若目标是成对转换（`'…'` → `"…"`），还需要捕获组 `'([^']*)'` → `"$1"`。

两个场景共同要求三件现有工具都给不了的能力：**glob 扇出**（path 枚举不出来）、**正则**（负向断言 + 捕获组）、**单次扫完全范围**（全稿 sweep 不能再逼模型逐条 Edit）。

### 约束

- 不得新开写入路径。批量写入必须复用 Edit 既有管线，以继承 `chapter_published`、`access_denied`、`is_folder`、readonly 字段等全部守卫，以及 working change 的可回滚性。
- 遵循 `.agents/rules/tools_path.md`：field-specific 路径严格返回该字段原始值。
- 遵循 AGENTS.md 规则 11 / 12（工具描述保持契约级别、不复述 schema）与规则 13（tool schema 保持静态）。
- 不改动 Drift schema，不引入 migration。

## 2. 目标

### 目标

1. 单次工具调用即可在 glob 限定范围内完成跨资源的正则替换，覆盖「角色改名」与「标点规范化」两个场景。
2. 替换前可空跑预览命中，且预览能让模型识别出误伤（如 `李明月` 混在 `李明` 的命中里）；空跑样本覆盖本次扫描到的**全部**命中字段，不按页切片。
3. 范围内一次处理完；超出扫描预算时标 `scan_truncated`，由模型缩小 glob 再调，不做字段级分页续跑。
4. 每个被修改的字段各产生一条独立可回滚的 working change，行为与 Edit 一致。
5. 批量写入撞到不可编辑目标（已发布章节、只读字段、AI 不可写文档）时按原因归类返回，不中断其余字段的处理。

### 非目标

1. 不覆盖 canvas 与 relations（原因见「已知妥协」）。
2. 不为 Replace 做专用的工具卡片体，第一版复用 `GenericToolCardBody`。
3. 不做跨字段的语义级改名（如同步 `characters.aliases`）—— 该字段不在 `editableFields` 内，需模型另行 Write。
4. 不替代 Edit。单点精确修改仍走 Edit。
5. 不提供 `max_fields` / `offset` 分页。批量工具一次做完范围内的命中；节流靠显式范围 + 扫描预算。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| `李明(?!月)` 全稿替换后 `李明月` 原样保留 | 单测 |
| 空跑不产生任何 working change | 单测 |
| 已发布章节被跳过且计入 `failed.chapter_published` | 单测 |
| 扫描超预算时 `scan_truncated: true`，已处理部分仍返回 | 单测 |
| 工具卡片显示「批量替换」而非英文原名 | 手动截图 |

## 3. User Stories

1. 作为作者，我希望改主角名时 AI 能一次扫完全稿并先给我看命中预览，以便我在落库前发现它会误伤同姓角色。
2. 作为作者，我希望批量替换后能像普通 AI 修改一样逐条 accept / reject，以便对个别章节保留原样。
3. 作为作者，我希望已发布的章节不被批量替换偷偷改掉，以便线上内容始终受我控制。
4. 作为维护者，我希望批量写入复用 Edit 的落库路径，以便新增的字段级守卫自动对批量生效，不需要改两处。

## 4. 解决方案

### 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A | `Edit` 新增 `paths` 数组，字面文本多目标替换 | 不新增工具；不改文本匹配语义；消灭往返 | 场景二 path 枚举不出来（Grep 32 条上限）；场景一无法写负向断言，中文人名前缀必误伤 | 放弃 |
| B | `Edit` 新增 `glob` + `regex` 参数 | 工具数不增，schema 集中 | Edit 的 `all` 默认 false、多处命中报错是刻意的安全设计，与批量「多处命中是正常的」前提相反；同一 schema 承载两套相反默认，描述无法自洽，模型选错概率高 | 放弃 |
| C | 独立 `Replace` 工具，glob 扇出 + 正则 + 空跑；一次扫完范围内命中 | 安全语义与 Edit 隔离；可按工具名单独授权；返回结构可为批量专门设计 | 新增一个工具的注册面（catalog / UI / i18n / prompt） | **推荐** |

### 决策

推荐 **方案 C**。理由：

1. **两个真实场景都否掉了 A。** 场景二根本枚举不出 path；场景一没有正则就无法安全执行。glob 与正则不是锦上添花，是准入条件。
2. **安全语义必须隔离。** Edit 的「默认只改一处、多处即报错」是它的安全内核；Replace 的存在前提是多处命中。把两者塞进一个 schema，工具描述要同时描述两种安全体制。
3. **授权粒度。** 工具按名字逐个授权给 agent（`aiToolCatalog` + `builtin_agent_tools.dart`）。独立工具才能对不同 agent 分别开关；并入 Edit 就失去了这个开关。

拒绝方案 A：见上，两个场景都跑不通。
拒绝方案 B：安全默认冲突，且同样要吃批量返回结构的复杂度，却拿不到授权粒度。

**不做字段级分页。** `max_fields` / `offset` 是 Grep「结果截断」语义，套到批量写入会逼模型续跑、改 pattern 时还容易带错 offset。批量工具一次做完范围内的命中；节流靠：显式 `path`/`glob`、扫描预算、`dry_run` 默认 true、返回体 samples/`failed` 封顶。

### 核心原则

1. **不新开写入路径。** 所有落库经由 Edit 的分发逻辑，Replace 只负责「选中哪些字段、算出新全文」。
2. **范围必须显式。** `path` 或 `glob` 至少给一个，不接受全库裸跑。
3. **默认不写。** `dry_run` 默认 `true`，必须显式传 `false` 才落库。
4. **一次扫完，预算截断。** 范围内命中字段一次处理；触及扫描预算则 `scan_truncated: true`，提示缩小 glob，不做 offset 续跑。
5. **失败归类而非平铺。** 一次 sweep 的失败按 `error_code` 聚合，不返回上百条独立错误。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| 整段旧文本 → 整段新文本 传给 `_replaceExactText` 恒得 `matchCount == 1` | 会误报 `ambiguous_old_text` | 该函数在整段文本中查找同一段整段文本，命中数必为 1；单测覆盖 |
| 模型能读懂空跑样本并自行收紧正则 | 误伤直接落库 | 样本按「匹配串 + 后 2 字」去重，并强制返回低频项；工具描述明确写出中文无词边界、需用负向断言 |
| 读取 1000 个字段的扫描预算够覆盖典型全稿 | 长篇小说被截断 | 返回 `scan_truncated` 标记，模型缩小 glob 再调 |

## 5. 方案实施

### 5.1 关键业务流程

Happy path（角色改名，两轮）：

```text
第一轮（空跑）
1. 模型调 Replace{pattern:"李明", replacement:"李泽明", glob:"/chapters/*/content"}
2. 收集候选路径：_collectResourcePaths → _looksLikeResourceFieldPath → glob → 可编辑字段预筛 → sort（与 Grep 一致，保证可复现）
3. 在扫描预算内逐路径读取文本、regex.allMatches（RegExp multiLine: true，对齐 Grep），记录全部命中字段并累积去重桶
4. 返回 samples（高频 10 条 + 低频 20 条）、matched_fields、total_matches、scan_truncated
5. 模型看到低频项里的「李明月」，判定误伤

第二轮（落库）
6. 模型改调 pattern:"李明(?!月)"、dry_run:false（参数变更即整次重跑，无 offset）
7. 逐字段 replaceAllMapped 算出整段新文本
8. 调 _applyEditToPath(path, 整段旧文本, 整段新文本, replaceAll:false)
9. 成功 → _stageTextChange 落一条 working change；失败 → 按 error_code 归类
10. 返回 applied_fields、total_replacements、failed、scan_truncated
```

失败路径：

```text
- path 与 glob 均为空          → missing_scope，不执行任何扫描
- 正则编译失败                 → invalid_pattern
- glob 编译失败                → invalid_glob
- 单字段撞守卫（已发布章节等）  → 计入 failed[error_code]，继续处理其余字段
- 扫描超预算                   → scan_truncated: true，返回已处理部分；描述提示缩小 glob
```

### 5.2 改动清单

#### NEW: `lib/shared/services/ai/tools_replace.dart`

文件头（遵循 AGENTS.md Dart 文件头规范）：

```dart
// 职责: AI Replace 工具 — 在 Read 可见资源文本字段中批量正则替换，复用 Edit 落库管线。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_grep.dart
//   lib/shared/services/ai/tools_edit.dart
//   lib/shared/services/ai/tools_resource_search_support.dart
// 遵循的 Rules:
//   .agents/rules/tools_path.md
part of 'tools.dart';
```

- 常量（对齐 Grep 量级）：`_resourceReplaceSearchFileBudget = 1000`、`_resourceReplaceSampleTop = 10`、`_resourceReplaceSampleRare = 20`、`_resourceReplaceContextChars = 12`。无 `max_fields` / `offset`。

- `_replaceDescription`：按规则 11 / 12，单参数的必填 / 默认值 / 取值范围只写在 schema 的 per-field `description` 里，工具描述只写 schema 表达不了的东西。

  ```text
  在小说工作区资源文本字段中批量正则替换。

  改单处文本用 Edit；跨多个资源改同一模式用本工具，典型场景是角色改名、称谓统一、标点规范化。

  必须提供 `path` 或 `glob` 之一限定范围。
  先空跑看命中，确认无误再传 `dry_run: false` 落库。
  中文没有词边界，`\b` 对汉字不生效；排除误伤要用负向断言，如 `李明(?!月)` 避开「李明月」。
  一次处理范围内全部命中；若返回 scan_truncated，缩小 glob 再调，不要分页续跑。

  返回：
  - 空跑：matched_fields、total_matches、samples（按「匹配串 + 后 2 字」去重的命中样本；覆盖本次扫描到的全部命中）。
  - 落库：applied_fields、total_replacements、failed（按 error_code 分组的失败字段）。
  - 两者都可能返回 scan_truncated。

  示例：
  - 空跑看命中：{"pattern": "李明", "replacement": "李泽明", "glob": "/chapters/*/content"}
  - 排除误伤后落库：{"pattern": "李明(?!月)", "replacement": "李泽明", "glob": "/chapters/*/content", "dry_run": false}
  - 引号成对转换：{"pattern": "'([^']*)'", "replacement": "\"$1\"", "glob": "/chapters/*/content"}
  ```

- `_replaceInputSchema`：结构对齐 `_grepInputSchema`（`tools_grep.dart:34`），`parse: _parseJsonMap`，`additionalProperties: false`，`required: ['pattern', 'replacement']`。

  | 字段 | 类型 | description |
  |------|------|-------------|
  | `pattern` | string | 正则表达式；literal=true 时按普通文本匹配。 |
  | `replacement` | string | 替换文本。可用 `$1`、`${1}` 引用捕获组，`$$` 表示字面 `$`；literal=true 时整串按字面写入。空字符串表示删除匹配内容。 |
  | `path` | string | 起始资源路径，限定替换范围。 |
  | `glob` | string | 限制资源路径的 glob 模式。 |
  | `dry_run` | boolean | 只返回命中预览、不写入，默认 true。 |
  | `ignore_case` | boolean | 忽略大小写，默认 false。 |
  | `literal` | boolean | 把 pattern 当普通文本而非正则匹配，默认 false。 |

- `_isReplaceTargetField(String path)`：可编辑字段预筛。**这是避免噪声的关键** —— 不预筛的话 `/chapters/{id}/word_count`、`/characters/{id}/aliases` 会一路走到 Edit 才被 `not_text_field` / `use_write_for_scalar` 挡下，一次 sweep 返回几十条无意义错误。

  ```dart
  /// Replace 只打 Edit 能写的文本字段。beats 的字段清单不在 _collectionSchemas 里
  /// （见 tools_outline.dart 的 _outlineBeatWriteHint），单独判。
  bool _isReplaceTargetField(String path) {
    final segments = _normalizeResourceDisplayPath(path)
        .split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return false;
    if (segments.first == 'outlines' && segments.contains('beats')) {
      return segments.last == 'title' || segments.last == 'content';
    }
    return _isEditableField(segments.first, segments.last);
  }
  ```

- `_expandReplacement(Match, String)`：捕获组展开。Dart 的 `String.replaceAll` **不解释** `$1`，必须走 `replaceAllMapped` + 手写展开。支持 `$1`–`$9`、`${n}`、`$$`；无效引用（`$0`、超出 `groupCount`）按字面 `$` 输出而不报错；`literal: true` 时整串按字面写入、跳过展开。

  ```dart
  String _expandReplacement(Match match, String template) {
    if (!template.contains(r'$')) return template;
    final buffer = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final ch = template[i];
      if (ch != r'$' || i + 1 >= template.length) {
        buffer.write(ch);
        i += 1;
        continue;
      }
      final next = template[i + 1];
      if (next == r'$') {
        buffer.write(r'$');
        i += 2;
      } else if (next == '{') {
        final end = template.indexOf('}', i + 2);
        final group = end > i + 2
            ? int.tryParse(template.substring(i + 2, end))
            : null;
        if (group == null || group == 0 || group > match.groupCount) {
          buffer.write(ch);
          i += 1;
        } else {
          buffer.write(match.group(group) ?? '');
          i = end + 1;
        }
      } else if (_isAsciiDigit(next)) {
        final group = int.parse(next);
        if (group == 0 || group > match.groupCount) {
          buffer.write(ch);
          i += 1;
        } else {
          buffer.write(match.group(group) ?? '');
          i += 2;
        }
      } else {
        buffer.write(ch);
        i += 1;
      }
    }
    return buffer.toString();
  }
  ```

- `_AiToolManagerReplaceMixin._handleReplace`：主流程，顺序见 5.1。落库分支调 `_applyEditToPath(path, 整段旧文本, 整段新文本, replaceAll: false)`。`_replaceExactText`（`tools.dart:2136`）在整段文本里查找同一段整段文本，`matchCount` 恒为 1，不会触发 `ambiguous_old_text`；多花一次 O(n) 扫描可忽略。

  失败归类**按 `error_code` 而非 `ok`** —— `_replaceTextErrorResult`（`tools.dart:2248`）返回的 map 没有 `ok: false` 键。

- 返回结构：

  空跑（改名场景实例）：

  ```json
  {
    "ok": true, "dry_run": true,
    "matched_fields": 112, "total_matches": 412, "distinct_patterns": 63,
    "samples": [
      {"text": "李明月", "count": 3, "path": "/chapters/ch_042/content", "line": 118,
       "context": "……只见李明月抬起头，眼里……"},
      {"text": "李明说", "count": 300, "path": "/chapters/ch_001/content", "line": 12,
       "context": "……李明说完转身就走……"}
    ],
    "skipped_fields": {"not_editable": 40},
    "scan_truncated": false
  }
  ```

  落库：

  ```json
  {
    "ok": true, "dry_run": false,
    "applied_fields": 110, "total_replacements": 356,
    "failed": {"chapter_published": {"count": 2, "sample_paths": ["/chapters/ch_003/content"]}},
    "scan_truncated": false
  }
  ```

  `samples` 取扫描到的全部命中上 **count 最高的 10 条 + count 最低的 20 条**去重后合并。误伤天然是低频的，低频那一半是它藏身的地方；高频那一半确认主意图没跑偏。`failed.sample_paths` 每类最多保留少量样例路径（建议 5），避免返回膨胀。

#### `lib/shared/services/ai/tools_edit.dart`

- 抽出 `_applyEditToPath(String path, String oldText, String newText, bool replaceAll)`，承载 `_handleEdit`（:114-172）现有的四路分发（canvas / outlines / novel singleton / 通用 handler）。返回**未经 `_attachWriteResourceLinks` 包装**的原始结果 —— 该函数会删掉顶层 `path` 键（`tools_support.dart:2068`），批量结果反而要从 `_links.self.path` 挖回来。
- `_handleEdit` 收缩为：解析入参 → 调 `_applyEditToPath` → 用自己的 `parsed` 调一次 `_attachWriteResourceLinks`。现有四个分支本来各自包了这一层，收敛到出口行为等价。
- **必须保留 `outlines` 分支在通用 handler 查找之前**：`outlines` 有注册的 `_DocumentResourceHandler`，而 `_editDocument` 把非 `lore` 的集合一律当 material 解析（:679），走到通用分支会返回 `not_found`。
- **必须保留 `!parsed.hasId` 守卫**（:149）：`_StructuredEntryResourceHandler.edit` 有 `title!` 断言（`tools_support.dart:699`），缺了会抛。
- 签名收 `String path` 而非 `ParsedPath`：`_handleEditOutline` 只读 `path` / `old_text` / `new_text` / `all` 四个键，且需要原始 path 字符串（它自己重新切 `beats/{index}`）。

#### `lib/shared/services/ai/tools.dart`

| 位置 | 改动 |
|------|------|
| :80-102 | 加 `part 'tools_replace.dart';` |
| :928-960 | catalog 加 `AiToolDefinition(name: 'Replace', group: AiToolGroup.edit)` |
| :982-1004 | mixin 列表加 `_AiToolManagerReplaceMixin`，排在 `_AiToolManagerEditMixin` 之后 |
| :1339 附近 | `_registerDispatch('Replace', AiToolGroup.edit, ...)`，走 **`_runToolObserved`** |
| :1709 附近 | `buildToolDefs()` 第一个列表里、`Edit` 旁边加 `ToolDef` |

**为什么不走 `_runMutationTool`**：批量工具没有单一的 `(path, oldText, newText)` 可预览；且 `AiToolCallBlock.hasDiff`（`lib/shared/models/ai_message_block.dart:141`）硬编码为 `isEdit || isWrite`，即使传了 diff 也永远不渲染。走 `_runToolObserved` 可完全不碰该 getter，审阅由 working overlay 的逐条 accept / reject 承担。

`AiSessionMode.canUseTool` **不用改**：`_specialModeTools`（`lib/shared/models/ai_session_mode.dart:57`）是白名单，Replace 不在其中即自动在 council / monologue / theater / roleplay 四个模式下被拒。

#### `lib/shared/services/ai/builtin_agent_tools.dart`

加 `'Replace'` 到 `builtinWriterSubAgentToolNames`、`builtinDefaultSubAgentToolNames`。

**不加** `builtinChroniclerSubAgentToolNames` —— chronicler 不做批量替换；同次改动补上 `'Edit'`、`'Grep'`（当前列表有 Write 无 Edit/Grep，局部修订与检索需要它们）。

不加 `builtinReadOnlyAgentToolNames` / `builtinExplorerSubAgentToolNames` / `builtinDreamerAgentToolNames` —— 这三个是定义上的只读 agent。

`defaultAgentToolNames()` / `defaultSubAgentToolNames()` 从 catalog 自动派生，不用改。

#### i18n 三件套

键名沿用 `ai.tool_name_*` / `ai.tool_action_*` 约定，`locale_keys.dart` 手工维护、无 codegen。

| 文件 | 改动 |
|------|------|
| `lib/shared/localization/locale_keys.dart` | 新增 `aiToolNameReplace`、`aiToolActionReplacing`，按字母序插入 |
| `assets/translations/en/ai.json` | `"ai.tool_name_replace": "Replace"`、`"ai.tool_action_replacing": "Replacing"` |
| `assets/translations/zh-CN/ai.json` | `"ai.tool_name_replace": "批量替换"`、`"ai.tool_action_replacing": "批量替换"` |

zh-CN 用描述性标签而非音译，对齐既有的 `tool_name_grep` =「内容搜索」。

#### `lib/shared/widgets/ai/tools/tool_card_descriptor.dart`

四个按工具名硬编码的 switch 各加一条。**漏掉任何一个都是静默降级**（渲染出英文原名或错误的视觉权重），analyze 和单测都发现不了。

- `toolActionVerb`（:51）→ `LocaleKeys.aiToolActionReplacing`
- `semanticPriorityForTool`（:175）→ 并入 `Edit` 所在的 `.high` 组
- `localizedToolName`（:204）→ `LocaleKeys.aiToolNameReplace`
- `toolHeaderSubtitle`（:405）/ `toolRowTarget`（:585）→ 新增 `case 'Replace':`，显示 `pattern → replacement` + 命中字段数。批量语义参考 `TodoWrite` 分支（:541 / :699）的 `'$verb (${items.length})'` 形态，不要套 `Edit` 的单路径形态

#### Prompt

- `assets/prompts/agent/review.md:7`：只读 agent 的禁用清单「不调用 Create、Write、Edit、Remove 或其他写入工具」补上 Replace。
- `assets/prompts/agent/orchestrator.md:115` 附近：补一句批量改名 / 统一称谓走 Replace 的引导。

#### 测试

**改** `test/shared/services/ai/tools_design_test.dart:107`：`expect(editTools, {'Edit'})` 是精确集合断言，改为 `{'Edit', 'Replace'}`。

**新增** `test/shared/services/ai/tools_replace_test.dart`。harness 抄 `tools_grep_test.dart:26-42`（真实内存 Drift，无 mock）。注意 `AiToolManager(contentService, workingOverlayService: overlay)` 不传 `novelReader` / `novelWriter`，测试不要覆盖 `/novel/*` 路径（会返回 `session_unavailable`）。

| 测试 | 断言 |
|------|------|
| 默认空跑不写库 | 不传 `dry_run` → 返回 `dry_run: true`，章节内容未变，无 active working change |
| 空跑返回去重样本 | `李明` 命中多种后缀 → `samples` 含 `李明月` 且 `count` 正确 |
| 空跑样本覆盖全扫描 | 误伤只出现在靠后的命中字段时，单次空跑仍返回该样本 |
| 负向断言排除误伤 | `李明(?!月)` + `dry_run: false` → `李明月` 原样保留，其余已替换 |
| 捕获组展开 | `'([^']*)'` → `"$1"` 得到成对双引号 |
| 字面模式 | `literal: true` 下 `a.b` 不当正则、`$1` 按字面写入 |
| 跳过已发布章节 | `failed` 含 `chapter_published` 且计数正确，该章内容未变 |
| 预筛不可编辑字段 | `word_count` / `aliases` 不进 `matched_fields`，不产生失败条目 |
| 缺少范围 | 无 `path` 无 `glob` → `missing_scope` |
| 扫描预算截断 | 超预算 → `scan_truncated: true`，已处理部分仍返回 |
| 逐条可回滚 | 每个成功字段一条 working change，`rejectWorkingChange` 后内容还原 |
| 非法正则 | `invalid_pattern` |
| special mode 拒绝 | 五个 special mode 下 `canUseTool('Replace') == false` |

### 5.3 Task Graph

```text
PR-1 Edit 分发抽取（_applyEditToPath，行为等价）
  └─ PR-2 tools_replace.dart + 工具注册 + 单测
       ├─ PR-3 i18n + UI descriptor
       └─ PR-4 SubAgent 授权 + prompt
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | `_handleEdit` 抽出 `_applyEditToPath` | 无 | 现有 Edit 相关测试全绿 |
| PR-2 | 新工具本体 + catalog / dispatch / ToolDef + `tools_replace_test.dart` | PR-1 | 新增单测全绿；`tools_design_test` 更新后全绿 |
| PR-3 | i18n 三件套 + `tool_card_descriptor.dart` 四处 | PR-2 | 手动截图确认卡片文案与视觉权重 |
| PR-4 | writer/default 授权 Replace；chronicler 补 Edit/Grep（不加 Replace）；review.md / orchestrator.md | PR-2 | 手动确认各 SubAgent 工具集 |

## 6. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | `李明(?!月)` 全稿替换后 `李明月` 原样保留 | `tools_replace_test.dart` |
| 功能 | `'([^']*)'` → `"$1"` 正确展开捕获组 | `tools_replace_test.dart` |
| 功能 | 扫描超预算时 `scan_truncated: true`，已处理部分仍可用 | `tools_replace_test.dart` |
| 安全 | 不传 `dry_run` 时不产生任何 working change、不改任何字段 | `tools_replace_test.dart` |
| 安全 | 无 `path` 且无 `glob` 时返回 `missing_scope` 且不扫描 | `tools_replace_test.dart` |
| 安全 | Replace 在五个 special mode 下被拒 | `canUseTool` 断言 |
| 错误处理 | 已发布章节计入 `failed.chapter_published`，不中断其余字段 | `tools_replace_test.dart` |
| 错误处理 | 不可编辑字段在预筛阶段排除，不产生失败条目 | `tools_replace_test.dart` |
| 兼容 | Edit 分发抽取后行为不变 | `tools_story_state_test.dart`、`tools_grep_test.dart` |
| 可维护性 | 工具描述不复述 schema 已有内容（AGENTS.md 规则 12） | 人工 review |
| UI | 卡片显示「批量替换」、有命中数、body 非空白 | 手动截图 |

测试命令（Flutter 测试必须串行）：

```bash
fvm flutter test test/shared/services/ai/tools_replace_test.dart
fvm flutter test test/shared/services/ai/tools_design_test.dart
fvm flutter test test/shared/services/ai/tools_grep_test.dart
fvm flutter test test/shared/services/ai/tools_story_state_test.dart
fvm flutter analyze lib/shared/services/ai lib/shared/widgets/ai
```

无 codegen 需求（不动 `@riverpod` / Drift schema / JSON 序列化）。

`test/shared/services/ai/prompt_token_baseline_test.dart:130` 会因多一个 ToolDef 而变动 —— 跑一次确认它是报告型还是有上限断言，若有上限则一并更新基线。

**UI 视觉验证（不可省）**：跑桌面端 app，在 AI 会话里实际调用一次 Replace（先空跑再落库），截图确认工具卡片文案、命中数、`GenericToolCardBody` 非空白、working overlay 出现 N 条可逐条 accept / reject 的变更。analyze 和单测都看不出这几处 UI 降级。

## 7. 评测

### 评测对象

- 被测能力：模型能否在空跑预览中识别出误伤，并自行收紧正则后再落库。
- 不测内容：正则引擎本身的正确性（由单测覆盖）；替换结果的文学质量。
- 输入来源：真实小说库，构造含前缀冲突的角色名（`李明` / `李明月`）。
- 输出判定：落库后 `李明月` 是否被破坏。

### 评测场景

| 场景 | 输入 | 期望 | 判定方式 |
|------|------|------|----------|
| 前缀冲突改名 | 「把李明改成李泽明」+ 库中存在李明月 | 模型先空跑、发现冲突、改用负向断言、李明月完好 | deterministic（检查李明月是否残留） |
| 无冲突改名 | 「把赵铁柱改成赵铁山」 | 模型可一轮空跑后直接落库 | deterministic |
| 全稿引号规范化 | 「把正文里的单引号都改成双引号」 | 单次落库完成范围内替换；若 scan_truncated 则缩小 glob 再调直至扫完 | deterministic |
| 越权尝试 | review agent 被要求批量替换 | 拒绝并说明只读 | manual |

### 自动化与人工评测边界

- 自动化覆盖：误伤是否残留、扫描预算截断是否正确、已发布章节是否被跳过。
- 人工抽查：空跑样本的可读性 —— 模型是否真的「看得出」低频项里的误伤，而不是靠运气。
- 仅作观察不阻断：模型收紧正则用了几轮。

## 8. Token 成本

| 维度 | 估计 | 说明 |
|------|------|------|
| 单次调用 token | 输入 ~200 / 输出 ~800 | 空跑返回最多 30 条样本，每条含 ~25 字上下文 |
| 调用次数 | 每次批量操作 2 次起 | `dry_run` 默认 true 强制两轮；仅在 `scan_truncated` 时额外缩小 glob 再调 |
| 上下文增长 | 不随小说长度线性增长 | 样本条数有上限，与命中数无关 |
| 模型档位 | 不限 | 工具本身无模型调用 |

**相比现状是大幅净减。** 现状改名 100 章 ≈ 100 次 Read + 100 次 Edit，每次 Read 返回整章正文（数千 token），总量在 10^5–10^6 量级。Replace 两轮 ≈ 2×10^3。

放大上界：仅当触及扫描预算（1000 字段）需缩小 glob 再调；典型全稿一次扫完。

`dry_run` 默认 true 是刻意用一轮 token 换安全 —— 相对于误伤后逐条 reject 上百条 working change 的代价，这笔交易明显划算。

## 9. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 模型忽略空跑直接传 `dry_run: false` | 模型图省事 | 误伤直接落库 | 默认 true；工具描述明确写出「先空跑」的工作流；working change 可逐条回滚 |
| 空跑样本没暴露误伤 | 误伤词与正常命中的后 2 字相同 | 误伤漏网 | 强制返回低频项而非只返回高频项；去重键含匹配串后 2 字；样本覆盖全部扫描命中 |
| 正则灾难性回溯 | 模型写出嵌套量词 | 单次调用卡死 | Dart RegExp 无超时机制 —— 列入已知妥协，靠扫描预算限制影响面 |
| Edit 分发抽取引入回归 | `outlines` 分支顺序错位 | 大纲编辑全部 `not_found` | PR-1 独立提交，先跑既有 Edit 测试确认行为等价 |
| 批量 sweep 产生大量 working change | 全稿替换 | 用户面对上百条待审 | `commitWorkingChanges(List)` 本就是批量签名，desktop 的 `pending_changes_detail_dialog.dart:276` 已支持批量接受 |
| UI switch 漏改 | 新增工具未同步四处 descriptor | 卡片显示英文原名、视觉权重错 | 验收强制截图；改动清单逐条列出 |

## 10. 已知妥协

```text
1. 妥协：不覆盖 canvas
   - 原因：/canvas 虽在 _rootCollections，但 _buildResourceHandlers() 未注册 canvas handler，
     _readRawResource('/canvas') 直接失败，资源树里只有 /canvas 一个光杆路径。
   - 影响：画布节点内的文本无法批量替换。
   - 升级触发：用户反馈画布文本需要批量改。
   - 后续方向：为 canvas 注册资源树 handler，或在 Replace 内单开 canvas 分支。

2. 妥协：不覆盖 relations
   - 原因：整个集合被排除在资源树外（tools_resource_search_support.dart:81）。
   - 影响：关系的 proof 自由文本可能残留旧名。
   - 升级触发：基本不会 —— 关系存的是 source_id / target_id 而非名字
     （tools_graph.dart:285），改名不会打断关系图；proof 是引文证据，保留原始措辞更合理。
   - 后续方向：无。

3. 妥协：aliases 无法同步
   - 原因：aliases 不在 characters.editableFields 内（tools.dart:390），预筛阶段即排除。
   - 影响：角色改名后别称字段仍是旧名，需模型另行 Write。
   - 升级触发：模型频繁忘记补这一刀。
   - 后续方向：靠 prompt 引导；不在批量工具里混进 Write 语义。

4. 妥协：无专用卡片体
   - 原因：EditToolCardBody 读的是 old_text / new_text，喂批量 payload 会渲染错；
     第一版落到 GenericToolCardBody。
   - 影响：卡片展示不如 Edit 精致。
   - 升级触发：用户反馈看不懂批量替换的结果。
   - 后续方向：新增 replace_tool_card_body.dart，渲染 samples 与 failed 分组。

5. 妥协：正则无执行超时
   - 原因：Dart RegExp 不支持超时，且无法在同一 isolate 内中断。
   - 影响：模型写出灾难性回溯的正则会卡住该次工具调用。
   - 升级触发：实际出现卡死。
   - 后续方向：在独立 isolate 中执行匹配并加超时。
```
