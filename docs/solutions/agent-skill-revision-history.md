# Agent Skill 版本历史与官方技能可编辑方案

## 修订记录

### 2026-08-12

- 变更摘要：实施过程中相对原方案的三处调整 —— `change_source` 去掉 `import`；
  历史表新增 `deleteForSkill` 并由 `NovelAgentSkillDao.hardDelete` 显式清子表；
  桌面历史入口改为对话框而非新增 home 内容区。
- 原因：
  1. 技能导入走 `createNovelLocalSkill` → `_persistInstall`，本就记为 `install`，
     独立的 `import` 值没有写入方；且 `import` 是 Dart 内置标识符，做枚举值易踩坑。
  2. 本库从未开启 `PRAGMA foreign_keys`，表定义上的 `onDelete: cascade` 全部不生效。
     实测删除技能不会级联删历史，也不会删既有的 `novel_agent_skill_references`
     （后者是本次发现的既有缺陷，已一并在 `hardDelete` 内显式清理）。
  3. `lib/desktop/pages/home.dart` 是 widget-decomposition 规则点名的存量 god-widget，
     新增内容区意味着往它的 build 里再加一种 selection 状态。
- 决策：全局 `PRAGMA foreign_keys` 未开启，本方案不改动它；仓库中其他表的
  cascade 声明同样处于失效状态，需要单独排查，不在本方案范围内。


## 1. 背景

### 现状

1. `novel_agent_skills`（`lib/shared/database/app_database.dart:531`）单表承载三种来源，official / marketplace 只是 `source_kind` 不同的本地快照，所有内容列都可写。
2. 附件正文存在独立表 `novel_agent_skill_references`（同文件 `:586`），运行时主查询不携带；写入统一走 `NovelAgentSkillDao.upsertWithReferences`（`novel_agent_skill_dao.dart:96`），过程中已按内容算 sha256（`:113`）。
3. 桌面 `lib/desktop/pages/home.dart:947` 与移动端 `lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart:72` 对非 `novel_local` 记录只打开只读详情面板，不给编辑入口。
4. AI 侧 `AgentSkillsRunCommandHandler._update`（`lib/shared/services/ai/agent_skills_run_command_handler.dart:123`）与四个 `reference-*` 命令都不检查 `source_kind`，可以直接改写官方技能快照，只在 reference 返回里附一句 warning（`:759`）。
5. 所有内容写入最终收束到 `InstalledAgentSkillsNotifier._writeUpdate`（`lib/shared/providers/novel_agent_skill_providers.dart:801`）。
6. `convertToNovelLocal`（同文件 `:379`）已实现并有测试覆盖，但没有任何 UI 或 AI 调用方。
7. 技能内容被覆盖后没有任何留档：`upgradeNovelAgentSkill`（`:514`）与 `overwriteInstall`（`:468`）整体替换快照内容。

### 问题

#### 技能内容不可回溯

```text
症状：AI 或用户改坏 prompt、删掉附件之后，无法查看改动前的内容。
根因：novel_agent_skills 只存当前状态，没有任何历史留档。
影响：一次 AI 工具调用可以覆盖用户手写的数十 KB 指令，用户既无法比对也无法参照旧版本改回去。
```

#### 官方技能的只读约束两端不一致

```text
症状：UI 上官方技能不可编辑，AI 工具却能随意改写它的 name / prompt / when-to-use / references。
根因：只读约束只做在 UI 路由层，没有做在数据层或服务层。
影响：约束形同虚设；而且被改写之后升级又会整体覆盖，用户的改动静默消失，且期间技能一直对外声称来自官方。
```

### 约束

- schemaVersion 28 已随发布版本出去，新表必须走新版本号和新的 `migrateToV29`，不得并进 v28（`.agents/rules/db-migration.md`）。
- 用户业务数据默认软删除。本方案对历史表及其附属 blob 表做物理删除，已获得用户对该范围的明确授权（`.agents/rules/data-deletion.md`）。
- 不引入新运行时依赖，sha256 复用已在用的 `crypto`。
- 内置技能（`assets/bundled_skills/`）走 `_bundledReferenceReadOnly` 拒绝写入，不入库，本方案不涉及。
- 不改动运行时热路径的 `novel_agent_skill_references` 表。

## 2. 目标

### 目标

1. 任意技能内容变更后，用户能在 UI 上查看变更前后的完整内容和 diff。
2. AI 一轮对话内的多次工具改动在历史中呈现为**一条**记录，而不是每次工具调用一条。
3. 官方 / 市场技能可以编辑，且编辑后不再声称来自官方、不再接收升级。
4. 历史存储不随编辑次数放大附件体积：只改 prompt 时不复制任何附件正文。
5. Run 工具的命令集合和 help 文本不变，AI token 成本零增长。

### 非目标

1. 不做恢复 / 回滚功能。历史只读，用户参照旧内容自己改回去。
2. 不做分支、不做多版本并存、不做跨设备同步。
3. 不改 `novel_agent_skill_references` 运行时表的结构或读写路径。
4. 不保留官方来源血缘（转本地后 `source_*` 三个字段照现有 `_asNovelLocal` 全部置 null）。
5. 不接入技能市场或远程撤销同步。
6. 不给内置技能记录历史。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| 编辑技能后历史面板出现新版本，内容与编辑前一致 | 手动检查 + provider 单测 |
| AI 一轮内连续 3 次 `reference-update` 只产生 1 条历史 | `agent_skills_run_command_handler_test.dart` 单测 |
| 只改 prompt 的 10 次编辑不新增任何 blob 行 | DAO 单测统计 blob 表行数 |
| 官方技能编辑后 `source_kind` 变为 `novel_local`，升级入口消失 | provider 单测 + 手动检查 |
| 超过 50 条后最旧版本及其孤儿 blob 被删除 | DAO 单测 |
| v28 库升级到 v29 后原有技能可正常读写 | `app_database_migration_test.dart` |

## 3. User Stories

1. 作为作者，我希望在 AI 改动我的技能指令后能看到它改了什么，以便判断这次改动是不是我要的。
2. 作为作者，我希望 AI 一轮任务里改的 5 个附件在历史里是一条记录，以便我能定位「这轮对话之前技能长什么样」。
3. 作为作者，我希望能基于官方技能改出自己的版本，并且清楚知道改完之后它不再跟随官方更新。
4. 作为作者，我希望查看旧版本时能一键复制指令或附件正文，以便粘回编辑器自己改回去。
5. 作为维护者，我希望历史存储不会因为附件被反复复制而膨胀到几十 MB，以便本地库体积可控。

## 4. 解决方案

### 方案对比：历史内容的存储形态

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A | revision 行内联 `references_json` 列 | 实现最简单，单表读取 | 只改 prompt 也复制全部附件正文；10 附件 × 20KB × 50 版 ≈ 10MB / 技能 | 放弃 |
| B | revision + 子表逐文件存正文 | 列表查询不背附件 | 仍然每版复制全部正文，只解决了查询问题不解决体积问题 | 放弃 |
| C | 内容寻址 blob + 清单表 | 正文按 sha256 全局存一份；只改 prompt 时零附件复制；被删附件仍可查看 | 多一张表，需要孤儿 GC | **推荐** |

### 方案对比：官方技能的可编辑性

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A | 保持只读，提供「复制为我的技能」fork | 官方安装仍可升级 | 用户要维护两条记录；fork 语义要额外解释 | 放弃 |
| B | 允许编辑，保留安装原始快照，升级时检测冲突 | 改了还能跟随升级 | 需要新增基线 hash 列、冲突弹窗、三路取舍 UI，复杂度最高 | 放弃 |
| C | 允许编辑，一经修改即转 `novel_local` | 复用已有 `convertToNovelLocal`，零新增列；语义诚实（改过的就不是官方的） | 改一个字就永久失去升级能力 | **推荐** |

### 决策

推荐组合：**存储用方案 C（内容寻址），官方技能用方案 C（一改即脱离来源）**。

选择理由：

1. 附件是 Agent Skill 包的主要体积来源，而绝大多数编辑只动 prompt。内容寻址让「改 prompt」这个高频动作的历史成本降到几百字节。
2. 「改过的就不是官方的」是最诚实也最省的语义 —— 转本地后 `upgradeNovelAgentSkill` / `checkUpgradeAvailable` 的 switch 天然走 `novelLocal` 分支返回 `NotTraceable`（`:601`、`:654`），升级入口自动消失，不需要任何新增状态。
3. 去掉恢复功能后历史表是纯 append-only，永不反向写回主表，实现和测试都少一整块（恢复时的 name 全局唯一冲突、恢复本身要不要记版本，这些问题一起消失）。

拒绝方案：

- **AI 侧新增 `history-list` / `history-get`**：模型读出旧版本再用 `update` 写回，就是变相的自动回退 —— 刚否掉的能力从后门进来。且 `_agentSkillsHelpText()` 是每次请求都进上下文的常驻成本。
- **migration 时 eager 回填全部技能的基线版本**：需要在升级事务里遍历所有技能与附件、逐个算 sha256，升级耗时和失败风险随本地数据量放大。改用懒回填（见 5.3）。
- **blob 用引用计数回收**：计数在异常路径容易漏减，导致永久泄漏或误删。改用扫描式 GC。

### 核心原则

1. **写入单点**：只有 `_writeUpdate` 产生版本，任何新增编辑入口自动被覆盖。
2. **append-only**：历史表永不被读回写入主表。
3. **内容寻址**：附件正文只按 sha256 存一份。
4. **turn 聚合**：AI 一轮对话 = 一条历史。
5. **不扩大 AI 工具面**：Run 的命令集合与 help 文本零改动。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| `ToolExecutionContext.sourceTurnId` 在所有 AI 改技能的路径上非空 | 聚合失效，退化成每次工具调用一条 | 退化行为可接受，不影响正确性；单测覆盖主聊天与 spawn 子 agent 两条路径 |
| 单个技能的编辑频率在几十次量级 | 50 条上限过小，用户丢失需要的历史 | 上限是 DAO 内常量，调整成本一行 |
| prompt 每次编辑几乎都会变 | prompt 进 blob 能省更多 | 当前把 prompt 留在 revision 行内，改为进 blob 是非破坏性追加 |

## 5. 方案实施

### 5.1 模型设计

```text
novel_agent_skill_revisions
- id: text, pk
- skill_id: text → novel_agent_skills.id, on delete cascade
- revision: int                    // skill 内自增，从 1
- turn_id: text nullable           // AI 聚合键；用户手动编辑为 null
- name / when_to_use / description / prompt: text
- category: text
- tags / agent_scopes: text (StringListConverter)
- content_hash: text               // 上述内容字段 + 附件清单的 sha256
- change_source: text              // baseline | install | user_edit | ai_edit | upgrade
- change_note: text nullable
- created_at: datetime
- unique (skill_id, revision)
- index (skill_id, created_at desc)

novel_agent_skill_revision_files
- revision_id: text → novel_agent_skill_revisions.id, on delete cascade
- path: text
- sha256: text                     // 指向 blobs，不加 FK 约束
- primary key (revision_id, path)
- index (sha256)                   // 供 GC 扫描

novel_agent_skill_blobs
- sha256: text, pk
- content: text
- byte_size: int
- created_at: datetime
```

字段语义补充：

- `content_hash` 是唯一的「内容有没有变」判据，覆盖 name / when_to_use / description / prompt / category / tags / agent_scopes 以及附件清单（path + sha256 有序拼接）。`enabled` / `sort_order` / `execution_blocked_reason` **不在其中**，所以启停和排序不产生版本。
- `change_source` 按 `.agents/rules/enum-naming.md` 用 snake_case，Dart 侧 `enum SkillRevisionSource { baseline, install, user_edit, ai_edit, upgrade }`（标识符即 dbValue）。`baseline` 专指懒回填出来的「最早已知状态」。
- `prompt` 留在 revision 行内不进 blob：它是 diff 的主体、几乎每次编辑都变，dedup 命中率低，进 blob 只会让单条读取多一次 join。列表查询本来就不 select 它。
- blob 没有 `ref_count`，回收靠扫描（见 5.3）。

### 5.2 ERD

```text
novel_agent_skills
  |
  | 1:N  (on delete cascade)
  v
novel_agent_skill_revisions
  |
  | 1:N  (on delete cascade)
  v
novel_agent_skill_revision_files ---- N:1（逻辑引用，无 FK）----> novel_agent_skill_blobs
```

删除策略：技能被删 → `NovelAgentSkillDao.hardDelete` 在同一事务里显式删 references、
历史与历史文件 → 之后触发一次 blob GC。**本库未开启 `PRAGMA foreign_keys`，
表定义上的 `onDelete: cascade` 不会真的执行**，删除必须由 DAO 自己完成。

### 5.3 关键业务流程

**用户手动编辑保存**

```text
1. UI 调 updateSnapshotFields(updated)
2. _writeUpdate(model, previous: target, changeSource: userEdit, turnId: null)
3. 若该 skill 在 revisions 表中没有任何行 → 先用 previous 内容 append 一条 baseline（懒回填）
4. 主表 upsertWithReferences 落盘
5. 算新内容 content_hash，与最新 revision 比对；不同则 append 新版本
6. append 后若该 skill 版本数 > 50 → 删最旧，并跑 blob GC
```

**AI 一轮内多次改动**

```text
1. tools_run.dart 构造命令时塞入 _turn_id = _currentToolExecutionContext?.sourceTurnId
2. handler 透传给 notifier，_writeUpdate 收到 changeSource: aiEdit + turnId
3. append 前先查该 skill 下 turn_id 相同的行：
   - 存在 → 覆盖其内容字段、content_hash 与 revision_files，保留 id / revision / created_at
   - 不存在 → 正常 append
4. 一轮任务无论调了几次工具，历史里只有一条
```

**官方技能首次编辑**

```text
1. 用户在只读详情面板点「编辑」
2. 调 convertToNovelLocal(id) → source_kind = novel_local，source_* 三字段置 null
3. 该次转换本身内容没变（_asNovelLocal 不动内容字段），不产生版本
4. 进编辑面板，后续保存按普通 user_edit 流程走
5. AI 路径同理：_update / reference-* 命中 sourceKind.isRemote 时先转本地再写
```

**失败路径**

- revision 写入与主表写入在**同一个 transaction** 内。历史写失败则整次编辑回滚，不出现「内容变了但没留档」。
- 懒回填读不到 previous（理论上不该发生）时跳过 baseline，只记新版本，不阻断编辑。
- GC 失败不回滚编辑：GC 在编辑事务之外单独执行，失败只记日志，孤儿 blob 下次 GC 会被扫到。

**blob GC**

```sql
DELETE FROM novel_agent_skill_blobs
WHERE sha256 NOT IN (SELECT sha256 FROM novel_agent_skill_revision_files)
```

触发点：裁剪掉旧版本之后、技能被删除之后、同 turn 覆盖之后。

### 5.4 改动清单

#### `lib/shared/database/app_database.dart`

- 新增三张表类 `NovelAgentSkillRevisions` / `NovelAgentSkillRevisionFiles` / `NovelAgentSkillBlobs`，注册进 `@DriftDatabase` 的 tables 与 daos。
- `schemaVersion` 28 → 29。
- `onCreate` 追加 `createAgentSkillRevisionIndexes(migrator.database)`。
- `onUpgrade` 追加 `if (from < 29) await migrations.migrateToV29(migrator);`。

#### `lib/shared/database/app_database_migrations.dart`

- 新增 `migrateToV29(Migrator m)`：按现有写法用 `_tableExists` 守卫建三张表，然后调 `createAgentSkillRevisionIndexes`。不回填数据。
- 新增 `createAgentSkillRevisionIndexes(GeneratedDatabase)`：建 `novel_agent_skill_revisions_by_skill_created` 与 `novel_agent_skill_revision_files_by_sha256`，命名遵循 `.agents/rules/db-index-naming.md`。

#### NEW: `lib/shared/database/daos/novel_agent_skill_revision_dao.dart`

- `appendRevision({skillId, content, changeSource, turnId, changeNote})`：查同 turn 行决定覆盖或新增；写 blob（`insertOnConflictUpdate`，同 hash 天然幂等）与 revision_files；返回 revision 号。
- `listRevisions(skillId, {limit, offset})`：只 select 元数据列，**不含 prompt**。
- `getRevision(id)`：全量 + join revision_files/blobs 还原附件。
- `latestContentHash(skillId)` / `hasAnyRevision(skillId)`：供写入判重与懒回填判定。
- `pruneRevisions(skillId, keep: 50)`：删最旧，物理删除；显式删子表，不依赖失效的外键级联。
- `deleteForSkill(skillId)`：技能被删时清空其全部历史。
- `gcBlobs()`：执行上文的扫描式 DELETE。

#### `lib/shared/models/novel_agent_skill.dart`

- 新增 `enum SkillRevisionSource`（含 `dbValue` / `fromDbValue`）。
- 新增 `NovelAgentSkillRevisionModel`（列表用摘要 + 全量两个形态）与内容 hash 计算函数 `agentSkillContentHash(...)`。

#### `lib/shared/providers/novel_agent_skill_providers.dart`

- `_writeUpdate` 签名改为 `_writeUpdate(model, {required NovelAgentSkillModel? previous, SkillRevisionSource changeSource = SkillRevisionSource.userEdit, String? turnId, String? changeNote})`；内部按 5.3 流程在同一 transaction 里落主表 + 历史，事务后触发 prune/GC。`previous` 必传（新建路径传 null），由编译器保证不漏。
- `updateSnapshotFields` / `replaceReferencesByName` / `rename` 增加可选 `changeSource` / `turnId` / `changeNote` 参数并透传。
- `_persistInstall` 以 `SkillRevisionSource.install` 写 revision 1。
- `upgradeSnapshot` / `upgradeNovelAgentSkill` / `overwriteInstall` 传 `SkillRevisionSource.upgrade`，`changeNote` 记版本号变化。
- `toggleEnabled` / `reorder` / `setExecutionBlockedReason` 不传 changeSource，内容 hash 不变自然不产生版本。
- 新增 `skillRevisionsProvider`（family by skillId）与 `skillRevisionDetailProvider`（family by revisionId）。

#### `lib/shared/services/ai/agent_skills_run_command_handler.dart`

- `_update` 与 `_replaceReferences`：命中 `existing.sourceKind.isRemote` 时先 `convertToNovelLocal(id)` 再写，返回体加 `converted_to_local: true` 说明。
- 所有写路径从 `command['_turn_id']` 取 turnId 传给 notifier，`changeSource: SkillRevisionSource.aiEdit`。
- `_referenceSnapshotWarning`（`:759`）语义作废：改成「已转为本地技能，不再接收更新」，或直接删除该方法并在 `_replaceReferences` 返回里给转换说明。

#### `lib/shared/services/ai/tools_run.dart`

- `_buildAgentSkillsCrudCommand` / `_buildAgentSkillsReferenceCommand` 塞入 `command['_turn_id'] = _currentToolExecutionContext?.sourceTurnId`。
- `_agentSkillsHelpText()` **不改**，不新增任何 history 命令。

#### NEW: `lib/shared/widgets/agent_skill/skill_revision_list.dart`

- 版本列表项：`v{n} · 相对时间 · 来源标签 · 摘要`，复用 `lib/shared/utils/relative_time.dart`。

#### NEW: `lib/shared/widgets/agent_skill/skill_revision_detail_view.dart`

- 与当前版本的 prompt 行级 diff（复用 `assets/translations/*/diff.json` 所在的既有 diff 组件），附件按 path 列出增/删/改，提供「复制指令」「复制附件正文」两个动作。

#### NEW: `lib/desktop/features/agent_skills/skill_revision_history_panel.dart`

- 左列表右详情；入口挂在 `setup_edit_panel.dart` 头部新增的「历史」按钮。

#### NEW: `lib/mobile/features/agent_skills/skill_revision_history_page.dart`

- 列表页 → 详情页两级；入口挂在 `_NovelAgentSkillEditPage` 的 AppBar overflow。

#### `lib/desktop/features/agent_skills/installed_skill_detail_panel.dart` / `lib/mobile/features/agent_skills/installed_skill_detail_page.dart`

- 新增「编辑」按钮：调 `convertToNovelLocal` 后跳编辑面板。不加确认弹窗，也不加说明文案。

#### i18n（`.agents/rules/i18n.md` 三件套）

`lib/shared/localization/locale_keys.dart` + `assets/translations/en/agent_skill.json` + `assets/translations/zh-CN/agent_skill.json`：

| key | zh-CN | en |
|-----|-------|-----|
| `agent_skill.history` | 版本历史 | Version history |
| `agent_skill.history_empty` | 暂无历史版本 | No versions yet |
| `agent_skill.history_source_baseline` | 初始状态 | Initial state |
| `agent_skill.history_source_install` | 安装 | Installed |
| `agent_skill.history_source_user_edit` | 手动编辑 | Edited |
| `agent_skill.history_source_ai_edit` | AI 修改 | Edited by AI |
| `agent_skill.history_source_import` | 导入 | Imported |
| `agent_skill.history_source_upgrade` | 升级 | Upgraded |
| `agent_skill.history_copy_prompt` | 复制指令 | Copy instructions |
| `agent_skill.history_copy_file` | 复制附件 | Copy file |
| `agent_skill.history_copied` | 已复制 | Copied |
| `agent_skill.edit_official` | 编辑 | Edit |
| `agent_skill.converted_to_local` | 已脱离官方来源 | Detached from its source |

### 5.5 Task Graph

```text
PR-1 数据层
  └─ PR-2 写入编排
       ├─ PR-3 UI
       └─ PR-4 官方技能可编辑
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | 三张表 + v29 migration + `NovelAgentSkillRevisionDao` + 模型与 hash 函数 | 无 | `fvm flutter test test/shared/database/` |
| PR-2 | `_writeUpdate` 改造、懒回填、turn 聚合、prune + GC、turnId 透传 | PR-1 | `fvm flutter test test/shared/providers/novel_agent_skill_install_flow_test.dart` 与 `test/shared/services/ai/agent_skills_run_command_handler_test.dart` |
| PR-3 | 共享列表/详情组件 + 两端入口 + i18n | PR-2 | 两端手动检查渲染，按 `.agents/rules/testing.md` 补 widget 测试 |
| PR-4 | 只读面板「编辑」按钮 + AI 侧转本地 | PR-2 | provider 与 handler 单测 |

### 5.6 Migration

```text
from version 28 to 29:
1. create table novel_agent_skill_revisions（_tableExists 守卫）
2. create table novel_agent_skill_revision_files
3. create table novel_agent_skill_blobs
4. create index novel_agent_skill_revisions_by_skill_created
5. create index novel_agent_skill_revision_files_by_sha256
6. 不回填任何数据
```

- **默认值**：存量技能升级后历史为空，第一次编辑时由懒回填补一条 `baseline`（内容为编辑前状态）。因此「升级后第一次改动」同样能看到改动前的样子。
- **回滚**：v29 只新增表，不改动任何既有表结构。降级回 v28 的旧客户端会忽略这三张表，数据不受影响。
- **失败处理**：沿用现有 `onUpgrade` 的 try/catch + `StartupFailureReporter`，失败整体回滚。
- **一次性补数据脚本**：不需要。
- 三者同步要求（schemaVersion + onUpgrade + Dart 模型类）见 `.agents/rules/db-migration.md`。

## 6. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | 编辑技能保存后历史新增一条，内容等于保存后的快照 | provider 单测 |
| 功能 | 存量技能首次编辑后历史有两条：baseline（改前）+ user_edit（改后） | provider 单测 |
| 功能 | 同一 `turn_id` 内连续 3 次 reference 写入后，该技能只多一条历史 | handler 单测 |
| 功能 | 历史详情能还原被删除的附件正文 | DAO 单测 |
| 性能 | 只改 prompt 的 10 次编辑后 blob 表行数不变 | DAO 单测 |
| 功能 | 版本数超过 50 后最旧一条被删，且其独占 blob 被 GC | DAO 单测 |
| 功能 | 官方技能点「编辑」后 `source_kind` 为 `novel_local` 且 `source_*` 为 null | provider 单测 |
| 功能 | AI 对官方技能执行 update / reference-update 后同样转为本地 | handler 单测 |
| 兼容 | v28 库升级到 v29 后既有技能读写正常 | `app_database_migration_test.dart` |
| 兼容 | `toggleEnabled` / `reorder` 不产生历史版本 | provider 单测 |
| 错误处理 | 历史写入失败时主表内容不变（同事务回滚） | provider 单测注入失败 |
| 可维护性 | 新增编辑入口无需改历史逻辑（写入单点在 `_writeUpdate`） | code review |

测试命令（Flutter 测试必须串行，见 `.agents/rules/testing.md`）：

```bash
fvm flutter test test/shared/database/app_database_migration_test.dart
fvm flutter test test/shared/providers/novel_agent_skill_install_flow_test.dart
fvm flutter test test/shared/services/ai/agent_skills_run_command_handler_test.dart
```

改了 Drift schema 后需跑 `make codegen` 并检查生成 diff。

## 7. Token 成本

不适用。本方案不新增 AI 工具命令、不改 `_agentSkillsHelpText()`、不改任何 prompt 片段，唯一进入命令 payload 的是内部字段 `_turn_id`（不进模型上下文）。相比现状 token 消耗持平。

## 8. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 孤儿 blob 泄漏 | GC 在编辑事务外执行且崩溃 | 本地库轻微膨胀 | GC 是幂等扫描，下次任意裁剪或删除时自动清理 |
| turn 聚合覆盖过度 | 用户在 AI 改动的同一 turn 内手动保存 | 手动改动被并进 AI 那条版本 | 手动路径 `turnId` 恒为 null，不会命中同 turn 分支 |
| 大附件写入变慢 | 单次编辑附带数 MB 附件 | 保存有可感延迟 | 附件正文按 sha256 幂等写入，未变化的附件不重写 blob |
| 用户误改官方技能后无法回到官方版 | 点了「编辑」并保存 | 失去升级能力 | 可从技能库重新安装官方版；历史面板保留改动前内容 |
| 被改写的市场技能脱离撤销同步 | 用户编辑了 marketplace 来源技能 | 已撤销内容仍可执行 | 已知妥协第 2 条，用户明确接受 |
| 历史被裁剪后旧内容永久丢失 | 单技能编辑超过 50 次 | 最早的版本不可查 | 上限为 DAO 常量，可调；UI 在接近上限时无需提示（第一版） |

## 9. 已知妥协

```text
1. 妥协：不提供恢复功能，用户只能复制旧内容自己粘回去。
   - 原因：恢复会把历史表变成可反向写回主表，带来 name 唯一性冲突、恢复是否记版本等一串语义问题。
   - 影响：回退一次改动需要用户手动操作两三步。
   - 升级触发：用户反馈频繁手工回退。
   - 后续方向：加「恢复为新版本」的线性恢复，不引入分支。

2. 妥协：当前版本的附件正文在 novel_agent_skill_references 与 blobs 中各存一份。
   - 原因：让历史机制反向改动运行时热路径的表，风险与收益不成比例。
   - 影响：一份冗余（相对于 references_json 方案的 50 份，可接受）。
   - 升级触发：本地库体积成为实际问题。
   - 后续方向：运行时表也改为引用 blob。

3. 妥协：prompt 不进 blob，只改描述的编辑仍会复制一份 prompt。
   - 原因：prompt 是 diff 主体、几乎每次都变，dedup 命中率低，进 blob 只增加一次 join。
   - 影响：极少数「只改 description」的编辑多存一份 prompt。
   - 升级触发：实测 prompt 重复率高于预期。
   - 后续方向：加 prompt_sha256 列指向同一 blob 表，非破坏性追加。
```
