# 关系图谱指南

关系图谱记录实体之间的有向关系。可以先从正文抽出已经写到的关系，也可以在写剧情之前先把人物关系网设计出来。每条关系都要有 `proof`；正文证据按来源填写 `chapter_id` 或 `scene_id`，两者不能同时填写。

## 路径

建立走 `Create`；真实变化、结束或恢复走 `Write`；录入修正走 `Edit`；误建关系或误录变化走 `Remove`。`GraphSearch` 查询当前生效关系，`Read` 包含已结束记录并按需读取历史。

| 目标 | 调用 |
|---|---|
| 建立一条关系 | `Create {"path": "/relations", "fields": {...}}` |
| 顺着某个实体展开关系网 | `GraphSearch {"type": "character", "id": "<id>"}` |
| 全部关系 listing | `Read {"path": "/relations"}` |
| 按条件过滤 | `Read {"path": "/relations?source_type=character&relation_type=ally"}` |
| 单条关系详情 | `Read {"path": "/relations/{id}"}` |
| 某场产生的关系 | `Read {"path": "/relations?scene_id=<场次 id>"}` |
| 某章产生的关系 | `Read {"path": "<章节 path>/relations"}` |
| 记录变化、结束或恢复 | `Write {"path": "/relations/{id}", "fields": {...}}` |
| 修正当前字段 | `Edit {"path": "/relations/{id}/relation_type", "old_text": "enemy", "new_text": "friend"}` |
| 单条关系的变化历史 | `Read {"path": "/relations/{id}/change_logs"}` |
| 读取一次变化 | `Read {"path": "/relations/{id}/change_logs/{change_id}"}` |
| 删除一次误录变化 | `Remove {"path": "/relations/{id}/change_logs/{change_id}"}` |
| 删除整条误建关系 | `Remove {"path": "/relations/{id}"}` |

`Read /relations` 支持的过滤参数：`source_type`、`source_id`、`target_type`、`target_id`、`relation_type`、`chapter_id`、`scene_id`、`status`。

一条关系复用稳定 ID，每次只表达一个当前主要类型。类型过滤仅匹配当前主类型，不搜索历史或依据文字。例如兄弟反目以 enemy 为主类型、血缘背景写入 proof，按 sibling 不会匹配。

## 字段

`Create /relations` 的实体类型、实体 ID、关系类型与 `proof` 必填；证据章节或场次 ID 可选且互斥：

| 字段 | 说明 |
|---|---|
| `source_type` / `target_type` | 实体类型，见下表 |
| `source_id` / `target_id` | 关系两端的实体 id，来自 Read / GraphSearch 结果 |
| `status` | active 表示生效，ended 表示已结束；Create 默认 active |
| `relation_type` | 合法值由 `source_type → target_type` 组合决定，见下表 |
| `chapter_id` | 可选，确立关系的证据章节 id；不能与 scene_id 同填 |
| `scene_id` | 可选，确立关系的证据场次 id；不能与 chapter_id 同填 |
| `proof` | 关系成立的依据（正文场面或设定说明，不要只重复 relation_type） |

实体类型取值：`character`、`faction`、`skill`、`item`、`location`、`chapter`、`foreshadowing`、`creature`。

### chapter_id、scene_id 与 proof

小说正文已经确立的关系，填确立它的证据 `chapter_id`（人物第 3 章相认、现在写第 40 章，仍填第 3 章）；剧本正文已经确立的关系，填证据 `scene_id`，不填另一个字段。

只有设定依据、正文尚未确立的关系，可以同时省略两种证据 ID，在 `proof` 中明确这是设定。不要填写计划揭示的未来章节或场次。场次作为证据使用，不是关系两端的实体类型。

`proof` 写依据，不写结论。正文里有场面就概括情节（「两人在雨夜互报家门，认出对方腕上同款胎记」）；设定阶段可以写设计依据（「同父异母，开篇尚未相认」）。「他们是兄妹」不是 —— 那是 `relation_type` 已经表达过的东西。

## 合法关系类型与方向

只有下列组合存在合法关系类型，表里没有的组合（如 `character → location`）建不了关系。契约与示例统一使用规范 snake_case 英文值；工具保留已有中文别名归一，不能凭中文近义词猜测新类型。

猜错不会静默写坏数据：`Create` 会报错，并把该组合的全部合法值列在错误信息里。`GraphSearch` 的 `relation_type` 是可选过滤：不知道就省略，禁止猜测。

### 读法：`A --type--> B` 读作「A 是 B 的 <type>」

**类型名描述的是 source 的身份**，不是 target 的。建之前把这句话读出来验证一遍，读不通就是 source / target 放反了。

三类偏离这条默认读法的，下表用记号标出：

- **[对称]** —— 两端可互换，谁做 source 都成立。同一对实体只建一条，不要正反各建一条。
- **[反读]** —— 类型名描述的是 target，读作「B 是 A 的 <type>」。只有 `subordinate` 和 `alter_ego` 两个（历史约定，改了会重解释存量关系）。
- **[动词]** —— 类型名是动词短语，按字面读，source 是主语。

### character → character

| 类型 | 读作 |
|---|---|
| `family` | A 与 B 有血缘/亲属关系 **[对称]** |
| `sibling` | A 与 B 是兄弟姐妹 **[对称]** |
| `friend` | A 与 B 是朋友 **[对称]** |
| `enemy` | A 与 B 敌对 **[对称]** |
| `lover` | A 与 B 是恋人 **[对称]** |
| `colleague` | A 与 B 是同事/同门 **[对称]** |
| `parent` | A 是 B 的父母 |
| `grandparent` | A 是 B 的祖辈 |
| `master_disciple` | A 是 B 的师父 |
| `subordinate` | **B 是 A 的下属** —— A 是上级 **[反读]** |
| `alter_ego` | **B 是 A 的化身/马甲** —— A 是本体 **[反读]** |

### character → faction

角色恒为 source，方向由实体类型确定。

| 类型 | 读作 |
|---|---|
| `member` | A 是 B 的成员 |
| `leader` | A 是 B 的首领 |
| `founder` | A 是 B 的创始人 |
| `ally` | A 是 B 的盟友 |
| `enemy` | A 是 B 的敌人 |

### character → skill

| 类型 | 读作 |
|---|---|
| `learned` | A 已学会 B **[动词]** |
| `mastering` | A 正在学 B **[动词]** |
| `mastered` | A 已精通 B **[动词]** |
| `creator` | A 是 B 的创造者 |

### character → item

| 类型 | 读作 |
|---|---|
| `owner` | A 是 B 的持有者 |
| `user` | A 是 B 的使用者 |
| `creator` | A 是 B 的制造者 |
| `former_owner` | A 是 B 的前持有者 |

### faction → faction

| 类型 | 读作 |
|---|---|
| `ally` | A 与 B 结盟 **[对称]** |
| `enemy` | A 与 B 敌对 **[对称]** |
| `subordinate` | **B 是 A 的下属组织** —— A 是上级组织 **[反读]** |

### skill → skill

| 类型 | 读作 |
|---|---|
| `prerequisite` | A 是 B 的前置技能（先学 A 才能学 B） |
| `branch` | A 是 B 的分支流派（B 是主干） |
| `evolves_to` | A 进化为 B **[动词]** |

### item → item

| 类型 | 读作 |
|---|---|
| `part_of` | A 是 B 的组成部分（B 是整体） |
| `evolves_to` | A 进化为 B **[动词]** |

### creature → creature

| 类型 | 读作 |
|---|---|
| `prey` | A 是 B 的猎物 —— **B 捕食 A** |
| `predator` | A 是 B 的天敌 —— **A 捕食 B** |
| `evolves_to` | A 进化为 B **[动词]** |

`prey` 与 `predator` 互为反向，同一组捕食关系任选一个方向建一条即可，不要两条都建。

### 最容易放反的四个

- `subordinate`：**source 是上级**。张三是李四的下属 → source 填李四。
- `alter_ego`：**source 是本体**。「克莱恩」是「愚者」的本体 → source 填克莱恩。
- `master_disciple`：**source 是师父**。张三拜李四为师 → source 填李四。
- `prey` / `predator`：**`predator` 的 source 是捕食方**。狼吃羊 → `狼 --predator--> 羊`，或等价地 `羊 --prey--> 狼`。

## 建之前先查

优先复用同一对实体的已有关系。先 `Read /relations?source_id=<source_id>&target_id=<target_id>`，再交换 source_id 和 target_id 读取另一方向，确认两端类型与依据；Read 包含 ended，不能仅凭 GraphSearch 无结果就 Create。存在多条存量记录时，按内容明确选择 ID；无法区分就停止写入，不能任取第一条、自动合并或宣称数据库保证唯一。有向关系保持原端点方向，不能通过换方向改变含义。

## 记录变化、结束与恢复

Write 必须提供非空 reason 和 proof，可选 relation_type、status，未提供的类型和状态保留当前值。chapter_id / scene_id 是本次完整证据，省略时当前位置清空；旧依据和旧位置留在之前的历史中。两种位置都为空时，proof 说明设定依据。返回 has_evidence_location=false 表示没有当前位置。

已有 friend 反目后，沿用 Read 返回的原关系 path：

```json
{"path":"/relations/<已读取的关系ID>","fields":{"relation_type":"enemy","reason":"确认对方出卖同伴后反目","proof":"两人在山门对质，甲确认乙出卖了同伴。","chapter_id":"<已读取的证据章节ID>"}}
```

分手但没有新的主要关系时，`Write` 原 lover 记录，fields 传 `{"status":"ended","reason":"分手","proof":"两人在桥边明确结束交往。"}`；保持 lover 类型。复合时先 Read 找到 ended 的原记录，再 Write `{"status":"active","reason":"复合","proof":"两人解释误会后重新确认交往。"}`。不能新建 ex_lover 类型，也不能用 Remove 表达剧情结束。

工具维护当前字段与 change_logs。不要生成或整包覆盖快照，不自行指定 change_id 或 recorded_at。重复提交相同状态、依据与最近原因不会追加一条变化。

## 修正录入与删除误录

字段录错使用 Edit。先 Read 具体字段，例如 `/relations/<关系ID>/relation_type`，再提交完整旧值到新值；`relation_type`、`status`、`chapter_id`、`scene_id` 必须匹配完整原值。proof 可精确替换片段，多处相同片段需 `all=true`。空位置 Read 返回 null，Edit 以 old_text="" 初始化，以 new_text="" 清空。切换章节/场次位置时先清空旧位置，再设置另一个；两次调用各自提交。

```json
{"path":"/relations/<已读取的关系ID>/relation_type","old_text":"enemy","new_text":"friend"}
```

Edit 只修正当前与最新快照，不新增历史；未修改的证据位置保留，无需 reason。它不是为过去某次事件改写剧情的入口。

查看演变时先 Read 当前关系，再按返回的 history_path 读取 change_logs。历史按录入顺序倒序返回，每条有稳定 id/path；baseline 是初始记录，不表示补出的旧剧情，也不计入变化次数。没有历史是合法的旧数据状态。

整次变化误录时，复制该 change 的 path 后 Remove。删除最新变化会恢复前一个状态及仍有效的证据；删除中间变化只移除该条，当前和后续变化保持不变。baseline 不能单独删除，初始关系就是误建时才 Remove 父关系。已删除证据保留历史文字，不能恢复失效链接。

返工旧章、补录倒叙或回忆时，证据位置与 recorded_at 都不代表完整故事顺序。不能凭章节号或场次顺序覆盖后续已确认当前态；无法判断时停止该关系写入并说明待确认处。

## 反模式

- **proof 写成结论**：`proof: "他们是敌人"` 等于没写依据。
- **证据 ID 填成当前处理位置**：关系在第 3 章确立却记成第 40 章，之后按章节回查关系全乱；场次证据同理。
- **方向随手填**：`subordinate` / `alter_ego` / `master_disciple` / `predator` 是最容易放反的四个，建之前按「A 是 B 的 X」读一遍。
- **给每对角色都连一条**：只建对情节有意义的关系，不要把角色表做成全连接图。
- **猜关系类型**：优先复制规范英文值，例如 `master_disciple`，已有别名容错不代表任意近义词都合法。
- **拼 id**：id 只能从 Read 或 GraphSearch 结果复制。
