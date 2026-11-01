# 依据、源码基线与历史核验记录

> 本文件保留原方案编写时的源码与验证记录；其中版本和“本轮”指对应历史核验，不代表此次文档拆分重新执行了构建、测试或接口验证。

[返回方案总览](README.md)

## 2026-10-10 导出与多轨范围更新

用户确认本方案同时支持直接导出和 Reveric 内多轨编辑后导出，先完成 Windows / macOS，共享底层保留 Android 接入能力。C 使用低清分段预渲染，不承诺拖动时实时多轨播放；音轨混合、裁切、视频叠层、工程保存和预览属于本方案，字幕、变速、转场库与调色仍排除。

以上为当时的范围记录。当前 Agent 接入与已实现编辑能力以 [Agent 合同](agent.md)和 [C 剪辑](editing.md)为准，历史排除项不覆盖后续确定的接口范围。

本轮源码核对结果只记录在[实施任务](README.md#实施任务)，本页保留方案方向与历史选型依据。

更新总览、制作、剪辑与验收合同；随后统一为单一目标版本，文档按主题平铺，移除旧分层目录和重复导航页。未实现产品功能，未运行 Flutter 测试、原生编码、数据库迁移或发布；文档检查不替代产品验收。

## 2026-10-07 源码核对与范围修订

2026-10-08 起以「片段」取代独立分镜（StoryboardShots、一镜一节点、剧本区分镜入口作废），本节以下决定已按 [制作文档](production.md) 同步。

下列条目是 2026-10-07 的历史快照，不表达当前实现进度。当前差距和验证结果以任务表为准；历史 schema 数字不能直接决定新迁移。

- 当时内容库 schema 20、AppDatabase 37。用户确认 VideoTasks、ScreenplayStagings/Revisions 尚未发布，直接按最终结构调整，不为这些中间结构增加兼容层；既有图片资产迁移保留数据。
- 片段复用聊天 Agent、资源工具和 WorkingOverlay。新增业务表为 EpisodeProductions 与 ProductionClips（取代 StoryboardShots）；片段与视频节点共用该表、以不可改的 kind 区分，只保存场次归属、场内顺序（仅片段）、标题、提示词、制作状态（仅片段）、生成配置及采用视频引用。镜头只是提示词中的分段文字。
- 提示词包含对白、画面和摄影要求，不拆字段或关联正文元素。状态为待制作、制作中、已完成；开始生成自动制作中，视频保存登记后自动采用并完成片段，失败保留制作中及原采用结果。不设置结果采用率指标。
- 当时 ImageAssets 仅支持图片，需要正式扩展为 Assets；图片/视频/音频、文本、场景、导演、道具及模板共用资产入口和生命周期，角色沿用现有模型。
- 当时 VideoTasks 尚无通用业务来源和结果资产列；E1 先完成结果登记必需的 Assets 数据层迁移，再补齐必填 novel_id/source_type/source_id、来源索引与可空 result_asset_id，连同资产登记和恢复完成后才可验收。重做历史直接查询任务，采用指针在片段或视频节点（同一张 ProductionClips）。
- 聊天继续使用 `<user-remind type/path/label>` 及其原有解析。片段提示词改用独立的 `<ref asset_id="…" label="…" />` 或 `<ref clip_id="…" label="…" />`，不携带 Read 路径或工具指令；正文内解析/序列化、编辑和视频媒体映射新增实现，只复用通用属性转义和 chip 视觉样式，不要求为引用协议注册资产 Read 路径。
- 当前 Agent 范围只含提示词文字编辑和已有 ref 保护，不新增资产列表、详情或媒体读取；素材选择由用户完成，保存层校验引用未被意外修改。资产 description 的新增暂缓，不计入本次数据改动。
- 当前 CanvasNodes 的 content 为便签、style 为样式。视频节点通过 production_clip_id 与 ProductionClips 一行一一对应，节点 JSON 不存提示词或配置副本；生成输入关系扩展现有 CanvasEdges，旧构思边维持原语义。
- 导演宿主已具备角色目录、场次工程保存和恢复；角色 catalogId 已在工程中，资产层登记唯一工程，不重复保存。动作目前是固定目录与采样函数，自定义 JSON 动作还需要对应编辑、校验和播放实现。

当前范围补充：专有制作包的导入与导出不纳入本方案，交付使用按成片顺序导出的视频文件及 Markdown/CSV 提示词表，现有备份恢复继续适配新数据；本方案不做成本预估或供应商价格表。

以下为原方案编写时的历史核验材料，其中 D 指拆分前的阶段。原方案 D1 包含 FFprobe、播放、原生包与基础编码，D2 负责导演输出和其他资产类型；实施方向以总览和当前制作文档为准。

## 方案编写时的源码基线

| 已核对实现 | 事实与本方案处理 |
|---|---|
| `lib/shared/database/novel_content_database.dart`：Screenplays/Seasons/Episodes/Scenes/Beats/SceneElements | 已有季、集、场次、节拍、结构化正文；不另造剧本身份。当时内容库 schemaVersion 为 19；已核对正式 v2.2.2 标签与发布记录，迁移见 [迁移与回滚](production.md) |
| `lib/shared/models/screenplay_element.dart` | 正文含场次头、动作、人物、括注、对白、转场、字幕、注释；没有镜头实体 |
| `lib/shared/database/novel_content_daos/screenplay_dao.dart` | 场序由当前集正文中的 scene_heading 顺序确定；不新增第二份场次排序列 |
| `lib/desktop/features/screenplay/script.dart` | 按集挂接共享正文编辑器，支持场次定位；保留此路径 |
| `lib/desktop/features/screenplay/scenes.dart`、`board.dart` | 已有场次列表、卡片和出场视图；场次板可以平移缩放，当前不是可编辑的摄影分镜或视频剪辑时间线 |
| `lib/desktop/features/canvas/widgets/canvas_region.dart` | 已能从引用节点跳回剧本场次；延续定位协议 |
| `Canvases/CanvasNodes/CanvasEdges`及`canvas_service.dart` | 已有引用/便签和视觉关系，尚无媒体生成输入合同；复用几何、选择、缩放与资源引用，不复用旧边承担执行语义 |
| `lib/shared/models/screenplay_workspace_state.dart` | 当前只有 section/season/episode/scene 选择；新增制作选择，不把任务运行态塞入导航快照 |
| `lib/shared/services/image_library_service.dart`、`ai/image.dart` | 已有图片导入、去重、生图与本地保存；图片库位于 AppDatabase，作品内容位于内容库，需明确跨库文件归属 |
| `lib/shared/models/ai_provider.dart` | 当时 `AiModelKind` 为 chat/image/embedding；现有视频能力见上方 E1 核对 |
| `lib/shared/services/canvas_export/format.dart` | `reveric.canvas` v1 明确排除媒体；保留该契约；专有制作包不纳入本方案，当前用视频文件及提示词表交付 |
| `pubspec.yaml` | 本次核对未发现专用视频播放、合成或三维导演依赖；不能把渲染/编码视为现成跨平台能力 |

移动端既有剧本功能保持现状；本方案不新增移动端短剧制作、视频配置或任务 UI，也不将 Android/iOS 适配、构建与验收列入完成条件。共享代码改动仍需保持既有移动端功能兼容。

## 实施所需账户与依赖

| 项目 | 使用方式与责任 |
|---|---|
| FVM SDK | 使用仓库已锁定 revision，启用 Impeller 与 Flutter GPU；不为三维改变 SDK 或 sqlite3 |
| flutter_scene / Flutter GPU | 固定 0.23.0 与 SDK 配套 GPU API；P 交付主应用桌面配置及功能证据，D 补桌面作品关联；核对间接依赖变化 |
| FFmpegKit/FFprobe/OpenH264 | 客户端媒体探测和处理使用固定版本原生包，保留源码/许可证/校验；不要求终端用户安装 CLI |
| Ark API Key | 仅使用用户的自定义 Provider key 配置。须已开通 Seedance 2.5，密钥不写方案或代码 |
| MiniMax API Key | 区分 api.minimax.cn 与 api.minimax.io，开通 H3 按量 API；不把旧视频资源包假定为 H3 额度 |
| Wan 3.0 API Key | 用户自有模型服务账户，Endpoint、Key 与模型区域匹配；按协议版本验证，不使用 Reveric 内置账户 |
| 用户 S3 凭据（F） | 访问用户指定 Bucket，上传参考视频并提供可读 URL；由本地对象存储设置维护，不进入生成任务快照 |
| 统一参考上传 | ReferenceStorageService 经用户自配 S3 准备参考地址；所有模型 client 共用，未配置时明确报错 |

## 核验范围

历史依赖解析结果只说明当时的组合可解析，不能替代当前构建或运行验收。实施时使用仓库锁定的 SDK 和依赖，分别验证协议、平台构建、媒体探测、对象存储互通及模型读取。

本次只清理过时文档，没有执行真实模型调用、远端存储请求或原生平台验收。实际结果由对应任务的验证记录承担。
