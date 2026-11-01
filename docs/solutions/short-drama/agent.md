# Agent 全流程、工具接口与分层权限

> 本文汇总已确定的 Agent 接入方向。接口示例是实施合同，不表示当前工具已经支持；实现和验收状态只在 [README 实施任务](README.md#实施任务)维护。官方技能更新另行排期。

[返回方案总览](README.md) · [工具实施合同](agent-tools.md) · [制作与画布](production.md) · [剪辑](editing.md)

## 目标与边界

Agent 可以在用户权限范围内读取剧本、规划分镜、排布画布、绑定参考素材、输出导演参考、生成图片／视频／音频、采用结果、处理素材、剪辑和导出成片。沿用现有聊天 Agent、资源工具、生成任务和业务服务，各步骤的内容与人工界面共用，成功修改可追踪，失败保留已完成成果。

工具分工固定为：业务资源使用 Create／Write／Edit／Read；生成使用 Run production；剪辑使用 Run editing；FFmpeg 素材处理使用 Run ffmpeg；文件内容读取使用 Run files；渠道与模型查询使用 Run providers。Read 不接受普通文件路径，也不因资源包含 path 字段就读取该文件。文件内容不要求登记到 Assets。

权限框架支持其他工具后续接入，首批启用图片、视频、音频生成和文件读取权限。不恢复所有 Write／Edit 的执行前审批，不增加独立的编辑、布局、剪辑或导出审批项。已有用户明确操作、业务校验和平台文件访问规则继续生效。

制作、导演和原生媒体操作以 Windows／macOS 为当前交付范围。权限模型、设置、审批卡和工具分发放在共享层，同时检查 Android；不因工具暴露而承诺 Android 已具备桌面制作、导演捕获或 FFmpeg 运行库。平台不可用时明确返回原因，工具 schema 保持静态。

## 工具入口

| 能力 | 入口与结果 |
|---|---|
| 剧本、分镜与片段 | 复用剧本资源及 `/clips` 的 Create／Write／Edit／Read；片段内容与生成配置保存到 ProductionClips |
| 制作画布 | `/episodes/{episode_id}/production/canvas` 及 nodes／edges；节点和布局可写，输入关系统一通过 clip.inputs 原子写入，edges 只读 |
| 导演编辑 | 复用 `/stagings/{staging_id}` 及对象、机位、轨道、关键帧资源 |
| 导演输出 | Write `/stagings/{staging_id}/output`，value 为输出文件路径；保留现有 preview 行为 |
| 渠道与模型 | Run providers list／read／models；通过 provider_id 和 kind=image／video／audio 一次查询模型列表及完整详情 |
| 生成 | Run production generate-image／generate-video／generate-audio，options.clip_id 指定片段 发起一次生成；Read 该集合及具体任务查询状态、历史和输出 |
| 采用结果 | Write clip 的 `selected_file_path` 字段，经媒体类型、可访问性和来源校验后更新采用结果 |
| 素材目录 | Read `/assets` 及 `/assets/{asset_id}` 返回元数据和文件路径；字段读取只返回字段原值 |
| 剪辑 | Run editing，按 editing_id 定位 VideoEditings，提供列表、创建、读取、编辑、撤销／重做、预览和导出 |
| 素材处理 | Run ffmpeg，接受 FFmpeg 兼容参数数组，使用应用打包的 FFmpegKit |
| 直接成片 | Write `/episodes/{episode_id}/production/canvas/output`，value 为目标文件路径 |
| 文件内容 | Run files read，options.path 为文件路径；经过 files.read 授权后返回文本或媒体内容 |
| 后台操作 | Run operations list／read／wait／cancel，按 run_id 查询、等待或取消当前会话操作 |

具体必填参数、默认值、结果、错误和 description 草案以 [工具实施合同](agent-tools.md)为准。长任务沿现有 SpawnAgent 的 background 语义返回 run_id，完成或失败后通知发起会话；取消请求和实际终态分开。

路径是资源地址，返回的 id 是稳定身份。模型 ID 可能含斜杠，模型详情地址由 listing 返回，调用方复制 path，不手工拼接。生成、导演输出、FFmpeg 和导出返回实际状态及可继续查询的任务引用，不能把已提交报告成已完成。

### 片段、画布与输入

Create `/clips` 创建内容；Write／Edit 修改提示词和配置；只有显式创建 generation 才提交模型。图片、视频、音频统一按 clip.kind 路由现有编排器，不能在普通内容保存、节点连线或页面加载时隐式生成。

Agent 可查询允许访问的素材目录、创建媒体节点、连接输入、调整用途与顺序、采用已有文件。普通提示词润色保留既有 ref 的身份、label 和出现次数。需要改变参考时，通过同一次明确的资源写入提交完整输入关系与新 prompt，复用 ProductionCanvasService 的保存校验；引用、节点及输入边一起成功或一起回滚，不能只放宽字符串替换校验。

输入来源校验所属作品／集、媒体类型、模型能力、用途、顺序和无环关系。缺少生成结果的上游节点可以保留连线，但会阻止依赖它的生成。画布坐标只改变空间排布，直接成片顺序仍由场次和场内 sortOrder 决定。

### 导演输出与直接成片

导演输出示例：

```json
{"path":"/stagings/staging_1/output","value":"media/exports/staging_1.mp4","fields":{"request_id":"staging_export_1"}}
```

PNG 输出静帧，MP4 输出预演；未指定选项时，沿用当前已保存工程的规格、第一个启用机位，以及静帧第 0 帧或整段预演。机位、帧或区间及 background／request_id 放在 fields 中，不增加 Write 顶层参数。两个 output 操作显式声明字段级 options，参数规范化与 `/_schema` 同步支持这些选项，不依靠忽略未知字段传参。输出仅在本次运行的内存中固定有效工程及修订，登记生成的参考资产并返回文件路径；不保存完整输出工程快照或重启恢复任务。新的输出请求使用当前工程，不复用旧任务的文档或临时帧；现有 `Write .../preview` 更新预览的行为保留。

直接成片示例：

```json
{"path":"/episodes/episode_1/production/canvas/output","value":"media/exports/episode_1.mp4","fields":{"request_id":"episode_export_1"}}
```

输出字段执行成片操作，画布根路径 Write 继续编辑布局。直接导出冻结本集场次内视频片段的采用文件，按场次／场内顺序合成，缺片段、文件不可读或规格无效时列出问题，不静默跳过，也不读取剪辑工程。剪辑后导出使用 Run editing export，读取指定工程修订。两者共用编码、校验、取消和文件交付能力。

受控相对输出路径以应用数据目录为基准；外部目标由用户明确提供或经平台文件选择器取得，不能依据模型自行猜测的路径覆盖已有文件。先在应用临时目录完成并验证输出，再交付目标位置。交付失败返回已保存的会话副本，后续可继续处理或交付该文件，不必重新生成素材。移动端 URI 经平台适配处理，不能当作普通文件路径。

### providers 与模型能力

Run providers 查询全局配置，list／read 读取渠道，models 按 kind 读取指定渠道的媒体模型，列表中的每项直接包含完整能力、默认参数与可用状态。list／models 一次返回全部条目，不接受分页参数，不返回分页字段。provider_id 直接传返回的原始字符串，结果中的模型 id 也保持原样，不做 URI 编解码；结果不携带资源路径。返回渠道 ID、名称、启用／可用状态、配置模型和有效能力，不返回 API key、认证头或其他凭据。查询结果结合模型目录、渠道覆盖及当前 adapter 实际支持范围；不能仅按供应商品牌或同名模型推断能力。

图像能力包含支持的生成／编辑方式、画幅与分辨率组合、参考图数量及参数约束；视频、音频沿用各自能力目录。未知型号明确标记能力未验证，并按现有服务的实际校验决定能否使用，不编造参数。用户配置变化只改变查询结果，不动态裁剪工具 schema。

providers 使用方法通过 `Run help providers` 提供，不注册 Read 资源或资源 schema，实时可用模型与渠道能力以查询结果为准。本轮沿用既有 skills，不修改技能主文件或 references 附件，也不维护技能能力表。生成调用按 Run 业务分组接入。

### 生成任务

`/clips/{clip_id}/generations` 映射已有 GenerationTasks，以 clip 为来源，不增加第二套生成表。Run production 冻结 prompt、模型、规格、实际参考及请求标识，再检查生成权限；批准后才上传参考并提交。普通片段编辑和 Read 不触发生成。

同一次提交复用稳定请求标识；重复调用返回原任务，相同标识但不同输入返回冲突。明确重做创建新任务，旧结果保留。任务请求不可变，后续 Edit clip 不影响已提交内容。运行中通过 Run operations cancel 取消；只有持久任务时 Run operations cancel 使用 options.task_id。两者进入同一取消服务，不允许任意写 status，也不能 Remove 任务冒充取消。

background 默认 true，先返回 run_id、实际阶段及已创建的 task_id，完成或失败通知原会话；false 等待最终结果。Run operations 提供 read／wait／cancel，wait 超时不取消任务，避免模型高频轮询。图片服务持久化 prepared 身份后再执行，视频的远端查询、同步图片／音频调用分别保留各自恢复合同。下载、登记和跨库结果应用失败只恢复原任务，不重新收费生成；submission_unknown 不自动重提。

允许生成不表示无限重做。沿用用户任务范围、节点数量／生成时长限制和现有批次约束；普通失败恢复不新增请求。任务已被上游接受后，不伪造上游取消，也不停止必要的结果保存与对账。显式取消记录 GenerationTasks.cancel_requested_at，迟到结果保留为资产但不自动采用；取消操作与上游任务状态分别展示。取消之前已提交的采用不回滚，提交竞争按真实结果返回。

## Run editing 与 Run ffmpeg

### 剪辑工程

目标实体是作品内容库的 VideoEditings／video_editings，记录类型 VideoEditingRow，字段为 id、title、document、revision 和时间戳／软删除列。document 复用 EditingDocumentConverter，不内嵌在 episode。制片场景由 ScreenplayEpisodes.editing_id 单向引用工程：新建 episode 自动创建并绑定空工程，已有集打开时仅在引用为空时补建；不读取旧时间线。工程本身不保存 episode_id，可独立创建。完整结构见 [剪辑工程模型](editing.md#工程模型与保存)。

Run editing 的子命令覆盖 list、create、read、apply、undo、redo、preview、export。list／create 使用可信的作品上下文；create 接收名称及画幅，创建有效空文档并返回新 id。其余命令通过 options.editing_id 指定工程；read 可按轨道或区间返回；apply 提交结构化命令数组和 expected_revision；export 指定 expected_revision、输出路径及规格。制作 Orchestrator 负责新建集自动绑定、打开旧集补建；历史有效剧集的空关联由一次性 initialization 任务补齐，已有非空关联保持原样。Agent 从 episode 查询结果取得 editing_id，统一使用 Run editing 操作工程。导入采用视频作为独立编辑；Run editing 不把 episode_id 或 project_id 保留为剪辑寻址别名。

apply 复用 EditingCommands，一组操作在同一快照上校验，整体保存并形成一次撤销记录。锁定、源区间、重叠、主轨自动磁吸及视频原声跟随与手工编辑一致。成功返回新修订和实际改动范围，失败不留下半组修改。撤销不得覆盖后来的人工作业；取消只影响尚未执行部分。

EditingSession 的文档、保存和撤销职责位于共享编辑会话，以作品上下文和 editing_id 定位，Agent 与界面使用同一实例。服务统一命名 EditingService。共享历史在进程内保留，最多缓存 32 个闲置工程，每工程 100 次撤销；活动界面与运行中的命令不回收。未提交人工输入、保存失败或过期修订均阻止覆盖；页面关闭仍可按已保存工程执行工具。字幕等编辑命令按当前 EditingDocument／EditingCommands／renderer 已实现能力暴露，不因 FFmpeg 支持某滤镜就宣称时间线编辑器支持对应可编辑效果。

VideoEditings 与导演 VideoStagings 均使用独立身份；SQL 表名分别为 video_editings、video_stagings，导演记录类型为 VideoStagingRow。目录内文档／会话模型及工具仍使用 EditingDocument、DirectorDocument、Run editing、editing_id、staging_id，不重复添加前缀。导演节点和 Revisions 的目标类型统一为 video_staging，资源路径仍为 `/stagings`。

本次不兼容旧导演／剪辑数据：不迁移 ScreenplayStagings 或 episode 内嵌剪辑，不双读旧表／列，不设置旧引用类型或旧寻址别名。旧 episode 打开时只补建新的空剪辑；旧导演及旧时间线内容不恢复，原媒体等其他业务数据保留。导演具体结构见 [模块衔接](director.md#模块衔接)，工程重构的状态见 P-02 和 C-05。

### FFmpeg 参数兼容

Run ffmpeg 提供 execute、probe、capabilities 子命令。execute／probe 通过 options.args 接收参数数组，直接调用现有 FfmpegRunner 和应用打包的 FFmpegKit／FFprobeKit，不执行 shell、不依赖系统 PATH。capabilities 返回当前平台实际版本、编码器、格式和滤镜，不承诺包含全部官方构建功能。

```json
{"command":"ffmpeg","subcommand":"execute","options":{"request_id":"cut_1","args":["-i","media/source.mp4","-ss","1","-t","3","-c:v","libx264","-c:a","aac","media/processed/cut.mp4"]}}
```

输出使用新文件，原媒体不覆盖；返回任务引用、处理进度、真实输出路径和探测规格。处理结果无需先登记 Assets 即可经 Run files 读取，也可显式导入资产目录、加入画布或剪辑工程。FFmpeg 本身不调用生成模型，不新建 GenerationTasks。

参数解析和首批选项／滤镜清单以 [FFmpeg 合同](agent-tools.md#run-ffmpeg)为准。每个显式输入匹配 files.read 权限能力；这里是权限检查，不是调用 Run files read。禁止网络、设备、清单及未经声明的隐式多文件 IO，字幕／字体等内部渲染由 editing export 处理，不直接透传任意脚本。生成／渲染服务对已冻结业务输入的内部读取不逐次弹窗。编码、抽帧和导出共用串行调度及取消，错误返回具体 token 或执行阶段。

## Run files 与文件授权

命令空间确定为 files，首批提供 read，后续文件动作可使用同一空间扩展。当前不因名称通用而新增任意文件修改、删除或 shell 功能。

```json
{"command":"files","subcommand":"read","options":{"path":"/Users/example/Desktop/reference.png"}}
```

Windows 可传普通绝对路径，如 `C:\Users\example\Pictures\reference.png`；应用返回的 `images/reference.png`、`media/processed/cut.mp4` 等受控相对路径，以应用数据目录为基准，不相对进程 cwd 或当前作品目录猜测。路径来自用户、文件选择器、附件或工具结果，不需要 asset ID。Run files 和工具素材导入只接受普通文件路径，不提供 Android 外部 content URI 适配。聊天文本附件由现有文件选择流程读取并加入上下文。

| 输入 | 返回内容 |
|---|---|
| 文本／JSON 等可读文件 | 分页文本、编码和截断信息，不执行文件内容 |
| 图片 | 规格及真正的图片内容块，按模型限制压缩，不仅返回路径 |
| 视频 | 时长、编码、尺寸、帧率等元数据；不抽帧，不直接向模型发送视频内容 |
| 音频 | 时长、编码、采样率和声道等元数据；未接入试听／转写能力时不能声称理解听感或对白 |

需要查看视频画面时，由 Agent 调用 Run ffmpeg execute，将指定时间点输出为图片文件；成功结果直接返回可见图片内容及会话副本引用，需要重新查看时可再调用 Run files read。抽帧只由 ffmpeg 提供，files read 不增加时间点参数、默认抽帧或视频帧附件类型。音视频元数据不能当作模型已经看过画面或听过声音的证据。

用户授权通过聊天审批卡或权限设置完成，Agent 不能通过参数声明自己已获批准。访问前解析并规范化路径、校验作用域和操作，再匹配 files.read：allow 直接读取，ask 挂起并等待用户决定，deny 返回 permission_denied 且不读内容。需要询问时展示目标文件、读取方式和内容将提供给当前模型的说明。批准前不读正文、不解码，也不发送文件内容；批准后重新核对目标身份，防止路径／符号链接变化将批准套到另一文件。文件缺失、无权限、格式不支持、取消和输出过大分别报告。

授权按调用或作用域生效，不要求每个 path 必须批准一次，也不新增路径白名单。仅本次批准只覆盖当前调用，即使下次仍读取同一路径，生效规则为 ask 时也需重新询问；session／episode／work／global 的 allow 则覆盖该范围内后续的文件读取。单次批准绑定实际目标及读取方式。持久 allow 是对应作用域内 files.read 的动作许可，会覆盖该范围内后续对其他可访问文件的读取，不只记住本次文件；审批卡和设置必须明确展示这一范围。只允许当前文件时选择“仅本次”，不能悄悄保存为整个 session 的许可。应用许可不能绕过操作系统文件权限或 Android 系统文件授权。资产元数据 Read 不读文件；`Read /assets/{asset_id}/file_path` 只返回原始路径字符串。

AgentMessage 和各模型适配层已有 ImageBlock，但当前工具结果经 Agent._toolResultEvents 统一编码成 JSON 文本。实施时补齐结构化工具结果中的图片内容块及消息持久化／恢复，避免路径或 base64 文本冒充模型可见图像。Run files 由普通 Agent 工具入口调用，本次不增加 Codemode 的 Run 或图片输出桥。不把大体积媒体原文写入普通日志或匿名上报。

### 多模态结果与聊天历史恢复

AG-03 补齐工具返回的文字和图片内容、会话文件归属及聊天保存与恢复。files.read 复用已有权限 gate；通用审批机制调整仍由后置 AG-01 承担，视频抽帧归 AG-06。已有 TextBlock、ImageBlock 及四个模型适配器继续复用。

文件读取服务返回读取数据与必要的文件信息，不生成 `<image name=... path=...>` 等模型提示文字。工具结果的消息组装层把读取数据转成通用内容块，并关联本次 toolCallId；通用 Agent 传递这些内容块，不负责文件保存、路径解析或识别资产 ID、视频时间点等业务字段。比如读取一张图片，本轮模型收到：

```text
ToolResultBlock（沿用本次 toolCallId）
  TextBlock：文件信息与读取结果
  ImageBlock：实际图片内容
```

这里参考实际工具调用后的消息结构：工具调用参数包含原文件路径，工具返回消息通过 call_id 关联该调用，输出内容中包含文字块与图片块。图片块只放图片数据和模型协议支持的参数，不另加名字、路径或时间字段；不照搬用户上传消息中的 `<image>` 文字包装。文件读取服务的返回值、内部通用内容块、各模型协议的工具返回消息分别由对应层转换，不能把整份多模态结果 JSON 编码成一段文字。

文件服务读取并按限额处理图片，把实际返回的图片保存为聊天使用的受控副本；普通文本及音视频元数据直接作为文字返回。聊天存储层保存原文字和图片引用，保留顺序。图片引用只需要 filePath 和 mimeType；不另设 assetId、timestampMs、sha256 或其他内容校验值。工具已经返回的说明文字原样保存，不用额外字段重建。副本使用独立文件路径，后续读取不覆盖已有副本；恢复时不自动重读源文件。

AiToolCallBlock 直接使用现有 result 保存 JSON，不新增 resultContent 或附件字段。文件结果以 content_format=session_files_v1 标识明确契约，content 数组保存有序 text（text）和 image（file_path、mime_type）引用。后台操作结果使用相同结构。模型消息先保留完整结果 JSON 文字，再按顺序组装内容块；图片字节单独存文件，base64 仅出现在运行时 ImageBlock 和模型请求，不写入聊天 JSON 或日志，不新增数据库列或附件表。

读取副本和处理产物存放于 ApplicationSupport/sessions/{session_id}/，使用唯一文件名。已经属于当前会话的文件直接复用，跨会话复制。正式素材采用先复制到素材目录。GC 沿用过期会话树的保护和筛选条件，先清理整组 session 目录，再删除消息、Todo、会话及 active 指针；文件失败保留整组记录，下次幂等重试。源文件不在 GC 删除范围。文件与数据库无法原子提交，文件已清而 DB 失败时，下次继续清理，历史图片暂时按缺件处理。完整备份包含 sessions，选择作品备份按消息结果和后台结果引用收集。

本轮发送与历史恢复共用聊天服务层的内容组装：按引用加载受控图片，交给 Agent 的始终是 TextBlock／ImageBlock。附件缺失、不可读、不可解码或超限时，在原位置只放包含文件路径的 TextBlock，其他文字原样保留；不发送错误块、不改变原工具成功状态、不弹错误或中断聊天，由模型自行判断后续动作。模型决定再次读取时属于新的工具调用。已经被上下文压缩移除的内容不重新注入，保留的内容不重复发送。

| 改动位置 | 职责 |
|---|---|
| Run files handler 与文件服务 | 返回读取数据和必要文件信息；图片按限额处理，音视频只探测元数据，不实现抽帧或拼接模型消息标签 |
| `lib/shared/agent/agent.dart`、消息与结果事件 | 接收和传递通用内容块，保留 toolCallId 和顺序，不增加文件存储或视频业务字段 |
| `lib/shared/models/ai_message_block.dart` 及生成序列化 | 沿用 result JSON，保存文字与图片引用，不新增字段 |
| `lib/shared/services/ai/agent_message_mapping.dart`、`session_persistence.dart` 与聊天事件消费方 | 主／子会话及后台结果保存相同内容；恢复时加载图片或保留路径文字，再组装模型消息 |
| `lib/shared/agent/client/` | 验证实际请求保留文字、图片顺序及工具调用关联 |

AG-03 使用固定文本和图片验证：本轮模型收到真实图片；保存重开后文字、图片字节及顺序一致；修改或删除源文件不影响受控副本；副本不可用时只保留路径文字，聊天继续。另覆盖子 Agent 终态合并、后台结果、旧文字结果和上下文压缩。视频／音频只返回元数据，不抽帧、不转写。AG-06 验证 ffmpeg 抽帧直接返回图片内容，以及 files read 再次读取副本；AG-03 不依赖 AG-06 完成。

## 通用权限规则与审批

### 动作注册

权限针对业务动作，不直接以顶层工具名判断。工具根据已校验的资源路径和参数声明动作、实际目标、作用域与审批摘要；普通调用、Run、子 Agent 以及 Codemode 中已有的 Create／Write 资源调用都经过同一权限执行入口；Codemode 不新增 Run 能力，新增资源动作使用同一 background 机制。模型不能自行提供 approved 或 scope 参数绕过解析。

首批动作是 generation.image、generation.video、generation.audio、files.read，默认均为 ask。将来其他工具注册新动作即可复用规则与审批；未接入的既有工具保持原行为，不因引入框架自动要求全量审批。新动作使用自己的默认值，不继承“允许图像生成”等无关授权，也不按运行权限修改静态 tool schema。

### 存储与继承

权限规则保存在应用库 reveric.sqlite 的独立 ToolPermissionRules 表（SQL 表名 tool_permission_rules），统一管理所有作用域。以下是计划新增的结构，当前尚未建表。Dart 字段使用 camelCase，表中列名使用 snake_case。

| 列 | 类型与可空性 | 含义 |
|---|---|---|
| id | TEXT，非空，主键 | 规则稳定 ID，更新或恢复时保留 |
| action | TEXT，非空 | 动作标识，如 generation.image、files.read；扩展动作不改表 |
| scope_type | TEXT，非空 | global／work／episode／session |
| work_id | TEXT，非空 | 所属作品 ID；全局规则使用空字符串 |
| scope_id | TEXT，非空 | 作用域对象 ID；全局规则使用空字符串 |
| decision | TEXT，非空 | allow／ask／deny，不持久化 inherit |
| created_at | 时间戳，非空 | 沿用项目时间戳写法，首次创建时设置 |
| updated_at | 时间戳，非空 | 创建、修改、软删除及恢复时更新 |
| deleted_at | 时间戳，非空 | 沿用项目软删除写法，0 表示未删除 |

作用域身份按下表组合，episode 携带 work_id，避免不同作品内容库之间混用身份。

| scope_type | work_id | scope_id |
|---|---|---|
| global | 空字符串 | 空字符串 |
| work | 作品 ID | 同一作品 ID |
| episode | 作品 ID | 该作品内的 episode ID |
| session | 作品 ID | 该作品内的聊天 session ID |

建立 `(scope_type, work_id, scope_id, action)` 唯一索引，包含软删除行，不把 deleted_at 加入唯一键。同一范围的同一动作始终复用一行：修改 decision 更新原行；恢复继承时软删除；再次设置时恢复原行并保留 id 和 created_at。查询只匹配未删除规则，并发设置由事务及唯一索引保证不会产生重复身份。

scope_type／decision 枚举、动作注册、字段组合、目标存在性和作品归属在 Dart 校验，校验及写入在同一事务边界内处理。不添加 SQL CHECK、外键或表级 UNIQUE。该表只保存持久规则，不保存工具参数、文件路径、单次审批请求或生成任务；“仅允许本次”由运行中的审批对象及聊天记录承接。

规则示例：

| action | scope_type | work_id | scope_id | decision |
|---|---|---|---|---|
| generation.video | global | 空字符串 | 空字符串 | ask |
| generation.video | work | work_a | work_a | allow |
| generation.video | episode | work_a | episode_3 | deny |
| files.read | session | work_a | session_s | allow |

上述规则使作品 A 默认允许视频生成，但第 3 集禁止；其他作品沿全局 ask。files.read 仅在作品 A 的 session_s 中允许，其他会话继续查找适用的上层规则。

不把规则塞进 ai_agent_settings JSON，不在各作品／episode／session 表分别增加权限字段，也不读取旧 ai_auto_approve_tools 作为授权。schema 和迁移版本在实现前按真实发布记录核定，遵守仓库仅用列、索引及既有主键／软删除写法的约束；本次文档不执行迁移。

| 层级 | 作用域 |
|---|---|
| 全局 | 当前应用内的通用默认规则 |
| 整部作品 | workId 对应的一部作品／整部剧，不是书库的作品集合 |
| episode | 指定作品内的一集 |
| session | 指定作品内的聊天会话；重开同一 session 仍有效，新会话不继承 |

查找顺序为 session → episode → work → global → 动作默认值，最具体的有效规则生效。decision 为 allow／ask／deny；“继承”表示该层没有有效规则，撤销规则按软删除处理。这里是用户可覆盖的偏好，因此全局 deny 可被用户明确保存的局部 allow 覆盖；不引入另一套隐藏的 deny 优先算法。

作用域由执行层解析实际目标，不能用当前打开页面替代。生成按 clip 查 episode 和作品；跨集批量逐项匹配。子 Agent 默认沿发起 session 的授权上下文执行，不能新建子会话扩大权限。跨作品操作不能携带来源作品的 session／episode 规则放行目标作品。无 episode 的角色生图等操作跳过该层；文件命令绑定可信的会话作品上下文，只有已验证的 episode 上下文才使用该层，不从文件名推断归属。

规则只由用户设置和真实审批操作修改，不向 Agent 开放自授权写入。权限在提交前读取最新状态，保存规则失败不能报告“已始终允许”；权限加载失败不能默认 allow。规则被软删除、目标失效或会话不匹配时不继续沿用缓存授权。

### 审批交互与生命周期

审批卡展示动作、目标和实际请求范围。生成显示渠道／模型、节点数量、规格、生成时长、参考输入和必要上传；文件读取显示实际文件和读取方式。用户可允许／拒绝本次，也可保存当前 session、episode、整部作品或全局规则；没有对应上下文的作用域不显示。设置显示最终生效值及来源，并允许恢复继承。

单次审批使用冻结请求，批准后不能替换模型、素材、目标文件或扩大批次。同类批次可合并展示，但逐项作用域和输入必须确定；后加请求重新匹配规则。拒绝、取消或停止后不提交；同一批准重复点击只执行一次。等待时收紧权限，提交前重新核对；上游已接受的生成继续查询和保存，不把修改权限解释为已撤销供应商收费。

沿用 AiToolApprovalRequest／AiToolApprovalController 的等待与决策通道，补齐 session／call 身份、可查询的待审批项、切换会话展示和取消清理。长期规则持久化到权限表；单次审批展示和结果沿用聊天工具记录；运行中的等待对象仅存在内存。应用重启不能把未批准请求当作已批准，恢复时重新核对规则；明确拒绝不能在后台静默转成允许。

历史核对：cade3cebb 在引入 Working Changes 时删除 Write／Edit 的执行前等待；a6c4f1114 随后移除 ai_auto_approve_tools 设置；现有审批类型仍在，但没有实际请求链路。接入必须同时覆盖执行入口、消息状态和桌面／Android 审批卡，不能只恢复旧设置开关。

## 全流程执行与恢复

后台采用 [background 与取消合同](agent-tools.md#后台执行与取消)，参考现有 SpawnAgent 的 started／result、会话持有和完成队列。新操作返回 run_id，可由 Run operations 查询、等待及取消；不能把取消请求已接收当作任务已停止。

```text
剧本／片段资源 → 制作画布与输入 → clip generation → 采用文件
                         ↑                          |
                  导演 Write output                 v
providers 查询／技能指导                     Run editing → export
文件路径 → Run files + 授权 → 可见内容          ↑
文件路径 → Run ffmpeg → 新素材 ────────────────┘

所有 Agent 操作 → 动作解析 → 作用域规则／审批 → 现有业务服务
```

用户提出制作目标后，Agent 可在已允许的动作和任务范围内连续执行；ask 暂停请求授权，deny 返回明确结果并保留此前成果。前置素材未就绪时等待其原任务，缺素材、未知提交、人工冲突和能力不支持时说明阻塞对象，不猜测文件或更换模型。

应用运行时可以离开制作页面继续任务；持久生成任务沿既有服务恢复。本次不新增全剧无人值守调度器、退出应用后继续执行的本地 Agent、通用导出任务存档或自动发布。导演／导出／FFmpeg 的操作引用用于运行期进度与取消；进程重启后不继续旧输出任务，用户再次发起时使用当前工程与输入创建新操作，不读取旧输出工程快照或补画旧临时帧。

## 实施与验收衔接

实施按可独立使用的能力交付：权限与 providers／files 查询、制作资源与生成闭环、导演／直接导出、共享剪辑会话与 Run editing、Run ffmpeg，最后以同一集验证全流程。对应状态只记在 README 的 AG 系列、P-02、C-04 和 C-05；新增能力依赖已有服务，不重复实现模型协议或渲染器。

主要改动位置为 `services/ai/tools*.dart`、新增 Run handler、`agent/tool_approval.dart`、工具结果消息链路、应用库权限 DAO／模型、共享设置／审批卡、`services/production/` 和 `services/editing/`。现有 `desktop/features/editing/session.dart` 的共享职责需要下沉。实现涉及超过 8 个文件及多个服务，应分批验收。

验收覆盖权限四层覆盖／继承与撤销、跨作品和子 Agent、批准前零内容读取／零上传／零生成、重复提交、拒绝／取消、未登记素材、文件路径与多模态消息、模型能力一致性、引用事务、剪辑冲突／撤销、单次输出输入一致性及再次输出采用当前工程、FFmpeg 参数与平台能力。普通测试使用固定文件和模拟上游，Flutter 测试串行且通过 FVM；真实模型评测另行显式开启。

回退时停用新入口，保留用户权限规则、片段、工程、任务及文件，不删除业务数据，不让旧代码覆盖新文档格式。工具及参数 description 的具体文案仍须在代码修改前单独确认。
