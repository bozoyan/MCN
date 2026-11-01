# AI 工具资源 Hypermedia Links 方案

## 问题

Read / Write 工具的路径语义对模型不友好：

- 同一集合有的用 **id**（`/chapters/{id}`），有的用 **title**（`/worldbuilding/魔法系统`）
- Listing 返回 `id` + `title`，模型常误用 title 拼路径
- 完整资源读不返回 canonical `path`，模型只能自己推断
- `outlines/.../beats` 等子资源打破通用的 `/{collection}/{key}/{field}` 心智模型

根因：**路径是隐式约定，而不是随资源返回的导航。**

## 目标

借鉴 REST HATEOAS，在 Read / Write 响应中附带 `_links` 超媒体导航：

- 模型 **复制 `_links` 中的 `path`**，禁止自行拼接第二段
- Listing 每条 entry 至少有 `path` + `_links.self`
- 单资源读展开 `fields` / `subresources` 链接
- 与 Glob 互补：`_links` 负责局部下一跳，Glob 负责全局发现

**非目标（本阶段）：**

- 不改变现有 path 解析规则
- 不统一 id / title 路径策略
- 不在 `_links` 中使用 working overlay 内部 id path

## 响应约定

### 字段名

使用 `_links`（HAL 风格），与业务字段（如 characters 的 `name`）区分。

### 单资源（完整读）

```json
{
  "path": "/chapters/chapter_abc123",
  "id": "chapter_abc123",
  "title": "第一章",
  "_links": {
    "self": { "path": "/chapters/chapter_abc123" },
    "collection": { "path": "/chapters" },
    "create": { "path": "/chapters", "tool": "Create" },
    "fields": {
      "title": { "writable": true },
      "content": { "writable": true },
      "status": { "read_only": true }
    },
    "subresources": {
      "beats": { "path": "/outlines/主线/beats", "type": "listing" }
    }
  }
}
```

- `create`：指向统一 `Create` 工具及目标 path
- `read_only`：标在 field link 上，提示不可 Write
- `writable`：标在 field link 上，提示可 Write
- 字段路径由资源 `path` + `/` + 字段名拼接（如 `/chapters/abc` + `/` + `content` = `/chapters/abc/content`），不在 `fields` 中重复
- `subresources`：仅 outlines.beats 等 schema 声明的子资源

### Listing

```json
{
  "type": "listing",
  "path": "/chapters",
  "_links": {
    "self": { "path": "/chapters" },
    "create": { "path": "/chapters", "tool": "Create" }
  },
  "entries": [
    {
      "path": "/chapters/chapter_abc123",
      "_links": { "self": { "path": "/chapters/chapter_abc123" } },
      "id": "chapter_abc123",
      "title": "第一章"
    }
  ]
}
```

Listing entry **不展开 fields**（控制 token）；需要字段链接时再 Read 单资源。

### 单字段读

```json
{
  "path": "/chapters/chapter_abc123/content",
  "value": "...",
  "_links": {
    "self": { "path": "/chapters/chapter_abc123/content" },
    "resource": { "path": "/chapters/chapter_abc123" },
    "collection": { "path": "/chapters" }
  }
}
```

### Write 成功

```json
{
  "path": "/chapters/chapter_abc123/content",
  "updated": true,
  "_links": {
    "self": { "path": "/chapters/chapter_abc123/content" },
    "resource": { "path": "/chapters/chapter_abc123" },
    "collection": { "path": "/chapters" }
  }
}
```

## Schema 扩展

在 `_CollectionSchema` 增加声明式元数据，链接由 schema 生成，不散落在各 handler：

| 字段 | 含义 |
|------|------|
| `readOnlyFields` | field link 标 `read_only: true` |
| `subResources` | 子资源（如 outlines → beats） |
| `createTool` | 根路径禁止 Write 时推荐的创建工具（默认统一为 `Create`） |
| `writeCreatesAtRoot` | `/collection` 可通过 Create 创建（skills/items 等） |

路径生成复用 Glob 遍历所用的 schema.fields 列表，与 `tools_resource_search_support.dart` 保持一致。

## 实现位置

| 模块 | 职责 |
|------|------|
| `tools_support.dart` | `_CollectionSchema` 扩展、`_buildResourceLinks`、`_attachReadResourceLinks`、`_attachWriteResourceLinks` |
| `tools_read.dart` | `_handleRead` 出口挂载 links |
| `tools_write.dart` | `_handleWrite` 出口挂载 links |
| `_readDescription` | 顶部增加 `_links` 使用说明 |

## 路径铁律（写入工具描述）

1. **永远复制** 工具返回的 `path` 或 `_links.*.path`，不要自己拼第二段
2. **id 集合**（chapters、characters…）禁止用 title/name 作路径段
3. **title 集合**（worldbuilding、materials、outlines、`.agents/rules`）禁止用 document id

`pathSchema` 仅描述 Hypermedia 导航与路径语法；可写字段由 Read `_links.fields` 中 `writable: true` 标示，Write 工具说明仅保留 Write 专有行为规则。

## 第三阶段（Write 描述精简）

- `_links.fields` 增加 `writable: true`（非 `readOnlyFields` 的字段），不含 `path`（字段路径 = 资源 path + "/" + 字段名）
- `_writeDescription` 从 ~80 行压到 ~25 行 + pathSchema，去掉字段表/枚举表/重复示例

## 后续阶段

- ~~Read `not_found` 智能 hint（检测 title 误用为 id）~~ ✅
- ~~精简 `_readDescription` 中与 `pathSchema` 重复的 path 说明~~ ✅
- relations listing entry 的 entity path 链接（暂缓）
- ~~根目录 `/` entries 从字符串升级为带 `_links` 的对象~~ ✅

## 第二阶段（2026-05-29）

- `_AiToolManagerPathHintsMixin`：Read/Write `not_found` 响应附加 `hint` 与 `error_code`
- `_buildRootDirectoryEntries()`：根目录 listing 对象化
- `_readDescription` 引用 `pathSchema`，去除重复字段表
- Glob 根目录遍历兼容对象化 entries

## 测试

- Read listing：`entries[].path`、`_links.self` 存在且可 follow
- Read 单资源：`_links.fields` 覆盖 schema 字段，每个字段含 `writable` 或 `read_only`
- Write 单字段：`_links.resource` 指向父资源
- outlines：`subresources.beats` 存在
