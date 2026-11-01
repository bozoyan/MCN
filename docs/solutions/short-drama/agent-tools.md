# Agent 工具实施合同

> 本文细化 [Agent 方案](agent.md)的参数、返回、后台通知及取消。实现和验收进度只维护在 [README](README.md#实施任务)，工具及参数 description 草案随本文列出，源码文案修改前按仓库规则确认。

## 共用约定

作品上下文、sessionId、sourceSessionId、sourceTurnId、callId 来自 ToolExecutionContext 和宿主，不接受模型通过 options 自行声明已授权或切换授权会话。业务 ID 从资源读取结果取得；新对象 ID 由应用生成，剪辑命令明确允许调用方指定的新片段 ID 除外。

Read 保持只读资源语义，不打开普通文件，不在读 episode 时创建剪辑。新增只读列表使用 offset=0、limit=50、最大 200；assets 与 clip generations 沿资源 Read 的 entries、total、limit、has_more 返回分页，Run editing list 只加载工程摘要。providers／models 查询一次返回全部条目，不接受 offset／limit，也不返回分页字段。执行型资源通过静态 schema 声明参数，不根据权限、用户渠道或平台状态修改工具定义。

资源详情和创建结果返回真实 id、path。同步修改返回 ok、id、path、updated 及实际改动；Run 命令返回结构化结果，不能只用 stdout 承载业务 ID。错误共用 error_code／error／hint；invalid_argument 表示参数错误，not_found 表示目标不存在，conflict 表示版本或请求标识冲突，failed_precondition 表示业务前置未满足，permission_denied 表示权限拒绝，unsupported 表示平台或能力不支持，resource_exhausted 表示限额超出，unavailable 表示运行依赖不可用。用户取消另带 cancelled=true，不作为可自动重试的服务错误。

## 后台执行与取消

### 对照现有机制

采用 `tools_subagent.dart` 的 background 契约：默认 true，启动后返回运行身份，完成或失败通知原会话；false 等待最终结果。运行归属、完成队列、切换会话和停止边界参考 `chat_agent_tool_dispatcher.dart`、`spawn_agent_run_providers.dart` 与 `chat_turn_runner.dart`。媒体运行不创建假子 Agent，不使用子会话 ID 冒充任务身份，不增加新的通用持久任务表。

取消接口参考当前 Codex 工具上下文中“启动返回 ID，后续按 ID 等待或终止”的控制方式。这里使用稳定 run_id，通过同一运行控制入口查询、等待和取消；取消等待与终止任务分开，终止请求回执与最终结果分开。

会话运行态增加媒体操作记录，登记 workId、ownerSessionId、sourceSessionId、sourceTurnId、callId、runId、kind、业务对象引用、冻结输入、状态、取消句柄和最终结果。一个 run 是一次执行，task_id 是生成服务的持久身份；二者分别返回，不用 run_id 代替 GenerationTasks.id。操作只能由所属会话或宿主明确授予管理权的父会话控制。

### background 参数与返回

| 入口 | 参数位置 | 默认 |
|---|---|---|
| Run production generate-image／generate-video／generate-audio | options.background | true |
| Write 导演／画布 output | fields.background | true |
| Run editing preview／export | options.background | true |
| Run ffmpeg execute／probe | options.background | true |
| Run files read | options.background | false |
| Run editing apply／导入素材 | options.background | false；整组原子提交 |

list／read 资源、工程创建、普通片段编辑、运行控制和 capabilities 都是短操作，不增加 background。background 不改变权限或业务事务语义。

所有输入先做纯参数和身份校验，再在第一次异步操作前登记运行。需要审批时后台操作返回 waiting_approval 并展示审批卡，批准前不执行正文读取、抽帧、上传或生成。批准后重新检查权限及冻结目标，进入 queued／running。同步模式等待同一个审批与执行结果；审批等待不计入实际处理时限。

后台回执形状如下，status 按实际阶段返回，task_id 只在持久任务已创建后出现：

```json
{"ok":true,"run_id":"run_1","status":"running","kind":"generation.video","task_id":"task_1","target_path":"/clips/clip_1","hint":"任务已启动，完成或失败后通知当前会话。"}
```

本地取消收到 native 回调并完成清理后才终止；取消请求超过 30 秒仍未收口时保留 cancelling，返回 cancel_timeout 诊断，不提前释放编码队列或谎报 cancelled。

本地状态为 waiting_approval、queued、running、cancelling，以及终态 completed、failed、cancelled、interrupted。后台准备失败也必须交付一次最终结果，不能只返回启动成功。completed 要求业务结果已经提交；文件操作还需文件校验完成。生成的 completed 表示原生成任务已完成登记及应执行的结果应用；供应商已接受不等于 completed。

最终结果带 ok、run_id、status、target_path、result；result 按操作返回 id、revision、task_id、files 等。失败另带 error_code／error／hint；取消带 cancelled=true、实际已完成范围及必要的 upstream_may_continue。Run files 的 result 可附真实图片内容块，不能把图像 base64 塞进普通 JSON 文本。

### 运行控制

统一使用 Run operations 控制当前会话的后台运行，不为每类工具重复设计状态和取消协议。

| subcommand | options | 返回 |
|---|---|---|
| list | status 可选；offset=0、limit=50，最大 200 | 本会话运行摘要及分页，不暴露其他会话 |
| read | run_id 必填 | 当前状态、kind、target_path、进度、task_id 和已有最终结果 |
| wait | run_id 必填；timeout_ms 默认 30000，范围 1 至 60000 | 有最终结果则返回；超时返回当前状态及 timed_out=true，不取消任务 |
| cancel | run_id 或 task_id 二选一；task_id 仅制作生成 | 接受停止时 accepted=true、status=cancelling；已经终止时 accepted=false 并返回现有终态 |

```json
{"command":"operations","subcommand":"cancel","options":{"run_id":"run_1"}}
```

取消指定运行不影响同一会话其他 run，也不回滚此前完成的内容编辑。重复 cancel 幂等；cancelling 尚未完成时返回 accepted=true 和当前状态。run 不存在返回 not_found；不属于调用方返回 permission_denied。不能用重新生成或重新提交代替查询原任务。

停止主回复只停止本轮同步等待和同步操作；已启动的 background=true 操作由会话继续持有。用户明确“停止后台任务”或点击指定运行的取消，调用相同取消入口。同步 foreground 的取消令牌传到实际执行器；后台启动回执的等待取消，不自动终止已登记的后台工作。关闭制作页面不取消后台运行。

### 取消如何落实

| 所处阶段／操作 | 取消行为与最终状态 |
|---|---|
| 等待审批／排队 | 撤销待审批项或移出队列，不读取、不上传、不提交；清理完成后 cancelled |
| 本地复制、探测、抽帧、导演渲染 | 逐段／逐帧检查取消，关闭流与句柄；取消 FFmpegKit 会话并等待 native 完成回调，清理本次临时文件后 cancelled |
| 剪辑 apply | 提交前取消则保持原修订；进入不可分割 DB 提交后等待真实结果，已提交就返回 completed，不伪装成回滚 |
| 输出文件最终交付 | 交付前可取消；已完成校验并交付则 completed。已交付文件不得因迟到取消被删除 |
| 生成尚未被上游接受 | 阻止新提交，取消可取消的上传／HTTP 等待，保留旧采用结果 |
| 生成已被上游接受 | 能确认远端取消时调用 adapter 的取消能力；不支持或结果未知时只停止当前 Agent 操作及后续编排，原任务服务继续查询、下载和登记，返回 cancelled 且 upstream_may_continue=true，不宣称供应商已停工或退款 |

为使“取消后不自动采用迟到结果”在重启后仍成立，GenerationTasks 新增可空 cancel_requested_at（Drift DateTimeColumn）。收到取消时先幂等记录；尚未提交的任务据此停止，已接受的任务继续对账。ProductionResultService 发现取消意图后只保留结果资产，不自动覆盖来源采用文件，用户仍可显式采用该历史结果。取消与结果采用经过同一来源串行控制，若采用已经提交就如实返回 result_applied=true，不回滚既成修改。这一列保存取消意图，不替代原任务 status；结果最终保存成功时任务可为 completed，但取消意图仍保留。

调用方操作的 cancelled 与上游生成任务状态分别展示。网络超时或停止轮询不能证明远端 cancelled；submission_unknown 仍按原合同处理，不能通过取消再创建实现隐式重试。停止后的后台自动续执行通知撤销，但工具卡保留最终取消状态和可查询的 task_id。

### 通知与资源释放

每个后台 run 最多向发起会话交付一次完成／失败通知。复用现有完成队列的排队、消费和回合注入方式，通知包含 run_id、kind、状态、业务 ID、实际输出或错误；不冒充用户消息或用户批准。当前 Agent 正在处理用户输入时排队，空闲时沿现有 completion turn 入口继续；会话切换不把结果发到另一会话。源回合已回退或任务已被明确停止时不再触发自动续执行。

运行态保留活动操作及待交付结果；通知消费后将最终摘要落入原工具记录并释放渲染器、文件句柄和临时输出。已保存的私有输出保留为文件；预览缓存沿原缓存生命周期。Run operations read 可从本会话历史工具结果返回终态摘要，不能借此重读已经过期的临时文件。

应用重启不恢复本地编码／文件操作或自动启动 Agent。GenerationTasks 按原服务恢复，取消意图一起生效；本地未完成操作标记 interrupted，用户或 Agent 在新回合显式重试。原 generation 的 request_id 重试仍定位原任务，不新增收费请求。

## episode 与剪辑关联

新建 episode 必须在原创建事务中建立有效空 VideoEditing 并写 editing_id。所有创建入口复用同一编排，不能仅由桌面按钮补建。空工程使用 EditingDocument.empty、当前剧本画幅和集标题／编号，不导入视频；Create episode 返回 id、path、editing_id、editing_revision=0。

打开已有 episode 的制片／剪辑工作区时，调用 ensureEpisodeEditing：editing_id 为空才补建新空工程，非空则校验并返回。创建与绑定同事务，两个打开请求返回同一 ID。旧 editing_document／editing_revision 从不读取；这个初始化规则是用户明确要求的生命周期，不是历史数据转换或旧字段 fallback。非空失效引用仍报错。

历史有效剧集中 editing_id 为空的记录，由一次性 initialization 任务 `episode_editings_v1` 补齐空工程；已有非空关联保持原样，每个作品库内原子补齐，任务失败不记录完成，可在下次启动重试。Agent 从 episode 的 Read／Create 结果取得 editing_id，统一通过 Run editing read／apply 等子命令读取和编辑工程，不另设剧集剪辑资源入口。

## 制作资源与 providers

### 输入关系的原子写入

`/clips/{clip_id}` 新增可读写 inputs，值为有序数组，每项为 source_node_id、role。顺序由数组位置派生，来源节点必须处于该 clip 的制作画布内；file_path／clip_id 在执行层从节点解析，模型不能提供互相矛盾的来源身份。图片仅允许 reference_image；视频和音频按 provider／model 的实际能力验证。

Write clip 同时支持 prompt、inputs 和已有配置字段。完整 inputs 表达目标关系，空数组表示断开全部输入；一旦 prompt 的 ref 身份变化，必须同次提供 inputs。未改变引用的文本润色不要求重复 inputs。提示词、节点引用及边在同一内容库事务提交，失败全回滚；独立 Edit prompt 保留既有 ref。Write inputs 不发起生成。Read edges 用于观察关系；关系写入统一通过 clip.inputs，不另开放会绕过引用事务的裸边写入。

Create canvas nodes 支持 video、image、audio、director、media；前四类可引用已有合法 ref_id 或创建新内容，media 使用 asset_id／file_path 二选一。外部 file_path 经 files.read 授权后复用导入服务复制到受控媒体目录，返回实际 media_path；不登记为资产也可建立文件节点。x／y 是有限数，未指定沿现有布局策略；批量位置修改保持既有原子 positions 合同。

采用通过 Write `/clips/{clip_id}/selected_file_path` 完成，value 是已保存的受控相对路径或 null。校验媒体类型、可读性及作品访问范围，null 只清除采用，不删除文件。外部路径须先导入，不将系统 URI 或任意绝对路径写入业务引用。

### 查询模型与素材

| 入口 | query／options 参数 | 返回 |
|---|---|---|
| Run providers list | enabled（boolean）、sort 可选 | ok、type=listing、entries；每项含 id、name、type、enabled、configured，无密钥／认证头 |
| Run providers read | provider_id 必填 | ok 及指定渠道的 id、name、type、enabled、configured |
| Run providers models | provider_id、kind=image／video／audio 必填；sort 可选 | ok、type=listing、entries；每项直接返回完整详情：真实模型 id、provider_id、kind、available、capabilities_known、capabilities、defaults、unavailable_reason 等 |
| Read `/assets` | type、search 可选 | 当前作品及全局共享素材的元数据，id、path、type、name、file_path、可用规格 |
| Read `/assets/{asset_id}` | 无 | 资产详情；file_path 只返回路径，不读取内容 |

providers 查询统一使用 Run，不挂载到 Read 的全局根、作品路径或资源 schema。`Run help providers` 提供固定调用说明，实时配置只改变查询结果。provider_id 使用返回的原始字符串，结果中的模型 id 也保持原样，斜杠和百分号不做 URI 编解码；结果不返回资源 path 或 models_paths。

`tools_run.dart` 将命令分发到 `providers_run_command_handler.dart`，由 `ProvidersRunCommandHandler` 校验参数并调用渠道／模型能力投影；不在跨作品资源路由中添加 providers 特判。

list／models 一次返回全部配置，不接受 offset／limit，也不返回分页字段。models 按 kind 筛选并直接包含每个模型的完整能力与默认参数，无需再逐个查询详情。sort 按字段升序，前缀 `-` 表示降序；list 支持 id、name、type、enabled、configured，models 支持 id、provider_id、kind、available、capabilities_known、unavailable_reason。未列出的子命令、未知参数、错误类型和无效 kind 返回 invalid_argument；渠道不存在返回 not_found；配置读取不可用返回 unavailable。查询只读，不修改供应商配置。

图像 capabilities 返回 modes、ratios、resolutions、sizes、min_references、max_references、像素／画幅限制；视频返回 modes、ratios、resolutions、durations、reference_roles 及每类输入限制；音频返回当前 adapter 可用的输入类型、数量、时长和输出格式。未知能力返回 capabilities_known=false 及原因，不填伪造数值。可用性只反映本地配置、访问资格与 adapter 支持，不探测远端权限或额度。实时渠道结果优先；本轮不更新官方 skill 内容或附件。

```json
{"command":"providers","subcommand":"list","options":{"enabled":true}}
{"command":"providers","subcommand":"models","options":{"provider_id":"openrouter","kind":"image"}}
```

## 生成资源

Run production 的 generate-image／generate-video／generate-audio 使用 options.clip_id 指定片段，options.request_id（必填，1 至 128 个 ASCII 字母、数字、下划线或连字符）、background（默认 true）。生成参数来自已保存 clip 和 inputs，不允许在本次请求中另传一套未保存 prompt／model。原始请求标识在同一次操作重试时保持不变，明确重做换新标识。

本地 task ID 由作品 ID、clip ID 和 request_id 的稳定哈希派生，使用 GenerationTasks 主键去重，不新增请求去重表。已存在相同标识时校验逻辑输入快照；不一致返回 conflict，一致返回原状态／结果。创建前冻结业务引用及文件身份，批准后复制输入、校验文件没有被替换再提交。任何来源变化都返回 conflict，不能在批准后换成新的采用文件。

Read `/clips/{clip_id}/generations` 返回任务摘要；具体记录路径为该集合下的 task_id，返回 id、path、kind、status、cancel_requested_at、模型／规格、错误、result_asset_id、result_file_path 和可继续操作的 run_id（若仍在运行）。输出是否自动采用单独返回 result_applied，不能把任务完成与当前采用混为一谈。

运行中取消用 Run operations cancel。重启后只有持久任务时，Run operations cancel 使用 options.task_id，经过同一取消服务；不允许任意写 status。终态请求返回实际终态和 accepted=false。取消不要求新的生成许可。失败后是否可以恢复下载／登记由原任务服务决定，复查原任务不自动重提。

## 制作节点便捷操作接入 Agent

本节是基于现有 UI 和共享业务编排的增量设计。目标是让 Agent 对一个真实制作节点执行与用户点击按钮相同的操作，直接取得已登记的资产、派生节点和来源关系。以下命令为待实现合同，不作为当前已开放能力写入运行时 skill。

### 入口与业务真源

沿用 `Run production`，不新增顶层工具。现有 generate-image／generate-video／generate-audio 保持各自语义；新子命令调用 UI 已用的共享服务，不要求 Agent 自行拼接 FFmpeg、导入文件、创建节点和补连线。

| UI 操作 | 新子命令 | 共用实现与结果 |
|---|---|---|
| 截取首帧／尾帧／当前帧 | capture-frame | `VideoToolOrchestrator.frame`；登记 PNG 资产，创建派生媒体节点 |
| 音视频分离 | separate-audio | `VideoToolOrchestrator.separateAudio`；提取音轨并创建音频媒体节点，源视频保留原声 |
| 静音 | mute-video | `VideoToolOrchestrator.mute`；创建无声视频的派生媒体节点 |
| 裁剪 | trim-video | `VideoToolOrchestrator.trim`；创建指定区间的视频节点，不修改剪辑时间线 |
| 视角与构图中的机位／打光 | derive-view | `ViewDeriveOrchestrator.create` 与现有图片任务提交；创建派生图片生成节点并等待本次生成结果 |
| 九宫格菜单与全景图生成 | image-preset | `ViewDeriveOrchestrator.createDraft`；创建带预设及来源输入的图片草稿，不自动提交生成 |
| 宫格切分及所选格高清 | split-grid | `GridOrchestrator.split/upscale`；登记裁切资产、分组及成员，高清分支提交既有图片任务 |
| 全景中的当前方向／四向截图 | capture-panorama | `PanoramaService.capture`；从同一全景图按明确视角生成图片节点 |

“全景预览”打开球面查看器、“结果”打开历史面板、“定位到分镜”及展开菜单属于界面导航，不新增等价的 Agent 打开窗口命令。Agent 使用资源读取、已有结果采用和 capture-panorama 完成业务目的。“作为参考”继续通过目标 `/clips/{clip_id}` 的 inputs 写入，不增加第二套连线接口。

### 参数与默认行为

所有新子命令必填 `node_id`，定位当前作品中的真实制作节点；画布、集、来源片段和当前采用资产由宿主解析。不能用 clip_id、asset_id 或标题冒充 node_id。以下参数均位于 options；表中未说明的字段拒绝，不开放任意节点 style 写入。

| 子命令 | 特有参数 | 执行方式 |
|---|---|---|
| capture-frame | `position=first/last/at` 必填；at 时必须提供整数 `at_ms`，其余情况禁止提供 | `background=true`；首尾帧使用现有提取实现，指定时间必须在媒体有效范围内，不以超出范围的 at 模拟尾帧 |
| separate-audio | 无 | `background=true`；输入必须有音轨，输出沿 UI 使用 M4A |
| mute-video | 无 | `background=true`；沿 UI 校验输入音轨并生成新视频 |
| trim-video | 整数 `start_ms`、`end_ms` 必填，`0 ≤ start_ms < end_ms ≤ 实测时长` | `background=true`；区间左闭右开，复用任意帧切点的重新编码流程 |
| derive-view | `preset=camera/light`、`provider_id`、`model_id` 必填；`args` 的字段见下文；`title` 可选 | `background=true`；创建草稿后走现有 generation.image 权限和任务流程，不以草稿已创建表示生成完成 |
| image-preset | `method` 必填，复用 `ImageGenerationMethod` 中除 free 外的既有预设枚举；`title` 可选 | 短操作，无 background；草稿返回 clip_id，随后可用现有 Write 配置和 generate-image 提交，与 UI 九宫格按钮的行为一致 |
| split-grid | `rows`、`cols` 必填，各为 1..5，总格数大于 1；`cells` 可选；`upscale` 可选为 2 或 4，提供时同时必填 provider_id、model_id | `background=true`；不传 upscale 只做本地切分；高清分支必须显式选择格子并校验模型支持该倍率 |
| capture-panorama | `views` 必填，为 1..4 项 `{yaw,pitch,fov,title?}`；角度为有限数，pitch 为 −85..85，fov 为 30..100，yaw 沿现有球面模型归一化 | `background=true`；方向全部显式提供，不读取鼠标拖动中的临时视角 |

`capture-frame position=at` 对应用户指定时刻，不依赖播放器是否打开、暂停或当前选中哪个节点。`last` 复用 `MediaService.extractFrame(last:true)` 解码尾部并保留末帧，不让模型用“时长减一个猜测值”寻找尾帧。

`derive-view args` 使用现有 `ViewPresetArgs`：camera 可传 yaw、pitch、framing；yaw 取 −180/−135/−90/−45/0/45/90/135/180，pitch 取 −60/−30/0/30/60，framing 为 extreme_wide/wide/medium/close/detail，默认 0/0/medium。light 可传 direction、brightness、texture、temperature、description；分别使用现有枚举，默认 front/moderate/soft/neutral，description 默认空。两类字段互斥；比例与分辨率沿现有编排计算，不再生成一套 Agent 专用预设提示词。修订共享参数校验时同时验证 UI。

`split-grid cells` 是从 0 开始、按行优先的格子编号数组，禁止重复与越界；省略或空数组表示全部，与当前本地切分一致。提供 upscale 时 cells 必须非空；不得因纯切分遇到问题自动转为收费高清。九宫格预设是 AI 生成图片草稿，宫格切分是已有图片的本地裁切，两者不能混为一个操作。

`capture-panorama` 只接受已有全景图片节点或已开启全景视图的图片媒体节点，按现有投影保存截图；四向请求使用同一 pitch/fov 和四个相隔 90° 的 yaw。它不把普通透视图自动变成可信的全景图，缺少全景素材时先创建 panorama 图片预设草稿。

### 来源、输出与画布关系

1. 校验节点属于当前作品及目标集，解析当前采用资产；缺少素材、媒体类型不匹配或能力不支持时返回实际错误。源节点与采用资产在运行中冻结，批准后、执行前再次校验；来源已换图／换视频则返回 conflict，不悄悄处理新的采用结果。共享编排接受同一份已校验来源，不能在运行中另读一份来源替换它。
2. 确定性媒体处理复用 `addDerivedOutput` 的 derived_output 来源边；图片派生复用 `addDerivedImage` 的有序输入及 reference_image 关系；宫格复用现有分组和成员关系。派生输出的来源边不等于已成为下一段视频的生成输入，绑定下一段仍须写该片段的 inputs。
3. 创建的新节点沿用源画布，默认由共享布局寻找源节点附近的空位。需要将 GridOrchestrator 依赖的 UI placement 回调抽成共享可调用的默认落点计算，UI 仍可传入交互落点；Agent 不传 BuildContext、屏幕坐标、选中态或播放器控制器，也不复制一套布局算法。
4. 新输出登记资产并返回画布身份；不替换源节点当前采用内容，不覆盖原素材，不用删除旧预览解决新的生成失败。已登记业务资产的失败清理沿项目既有生命周期处理，不在工具 catch 中新增 hard delete。

最终 `result` 统一包含 `source_node_id`、`source_asset_id`、`outputs`；每项有 `node_id`、`node_path`、`type`、`asset_id`（已有实际资产时）、`clip_id`（生成草稿时）及可用的 `file_path/width/height/duration_ms`。`node_path` 是 `/episodes/{episode_id}/production/canvas/nodes/{node_id}`。宫格另返回 group_node_id 和按原格子编号排列的成员映射；全景另返回各 view 与输出的对应。草稿明确 `generated=false`，不伪造文件或 asset_id。

生成操作除 run_id 外保留真实 task_id；多格高清返回每格对应的 task_id 和结果。部分成功返回已完成 outputs 及逐项 failures（含节点／格子／视角、阶段、错误码和实际诊断），`ok=false`，不把整组说成成功，也不在重试时重新生成成功项。Agent 返回保留底层错误和必要日志，凭据脱敏；UI 另外转换为可读提示。

### 执行、权限与平台

复用 ToolOperationManager 的登记、后台通知、等待和取消；不新增任务表、配置开关或请求去重体系。重复提交是新的操作，Agent 查询已经启动的操作使用 Run operations。image-preset 只创建可编辑草稿；derive-view 与 split-grid 的高清分支调用现有图片生成服务，保留它们的授权与结果采用规则。

文件读取使用现有 files.read 规则并按实际来源判断授权；远端图片生成使用 generation.image。审批展示实际源节点、当前资产、操作和模型，批准前不解码、裁切、上传或生成。纯草稿的元数据写入遵循现有制作资源写入规则，不增加新的授权种类。

现有 UI 编排并非全部已支持外部取消：接入时需把 operation 的取消令牌沿共享 Orchestrator 传到媒体执行、复制和生成流程。FFmpeg 取消必须等待原生回调，不能只把工具状态改成 cancelled；批量操作在每项前检查取消，保留并返回已提交结果。需要扩展方法签名时由 UI 和 Agent 共用，不在 Agent handler 中重写处理主体。

截图中的制作 UI 位于 desktop。视频截帧、分离音轨、静音和裁剪沿现有 FFmpeg runtime，只支持 Windows/macOS；Android 返回 unsupported。图片草稿、派生生成、宫格与全景处理使用 shared 服务，接入时显式验证 Windows/macOS/Android 的离屏图片处理、资产保存和平台能力；不能由于当前 UI 只有 desktop 就把共享工具整体禁用在 Android，也不能未经运行验证声称三端均已支持。工具定义保持静态，运行时说明具体限制。

### 与现有文件工具的分工

- 检查少量视频画面：继续优先 `Run ffmpeg frames`，返回带时间标注的检查拼图；时间线检查使用 `Run editing frames`。
- 获取可继续制作、连接为参考的首帧或尾帧：使用 production capture-frame，返回独立图片资产与节点；不把检查拼图当正式首帧。
- 任意文件转码或滤镜处理：继续使用 ffmpeg execute；基于已选制作节点执行现有便捷操作：使用本节 production 子命令。
- 结果采用、读取原文、定位分镜和参考绑定继续使用已有资源接口；本节不增加重复入口。

### 源码接入与验收

路由位于 `lib/shared/services/ai/tools_run.dart`，节点操作 handler 放入现有 `lib/shared/services/ai/media/`，共用 `ProductionToolHost`、ToolOperationManager 和上述 Orchestrator。`tools_production_schema.dart` 只按实际读取需要补充节点的预设、全景或分组摘要，不允许通过原始 style map 绕过命令校验。工具卡与运行条共用的本地化动作映射同时补齐，检查 shared 组件在 desktop/mobile 的使用。

实现涉及路由、handler、若干共享编排、资源返回、UI 文案和测试，预计超过 8 个文件；按“视频节点操作 → 图片派生与宫格 → 全景取景”分别交付，每批带自己的技能说明与回归，不用先搭新服务或新数据库结构。当前 UI 继续调用相同业务真源。

验证至少覆盖：源节点与作品／集隔离、采用结果变化、首尾及指定时间边界、无音轨、裁剪区间、源资产不变、真实派生边与节点；宫格尺寸／索引／方向及选择顺序；草稿不提交任务、模型与预设一致；生成批准／拒绝／取消、批量部分失败和迟到结果；全景角度、截图输出及失效来源；中文／英文工具卡和运行条。

复用并扩展 `test/shared/services/ai/tools_run_test.dart`、`test/shared/production/media_service_test.dart`、`test/shared/production/image_generation_test.dart`、`test/shared/production/panorama_capture_test.dart`、宫格共享处理与 UI 测试，以及 `test/desktop/widgets/ai/tools/run_production_tool_card_test.dart`。Flutter 测试通过 FVM 串行执行；视频操作还要用真实 macOS/Windows FFmpegKit 验证。源码分析、mock 成功和模型真实画面验收分别报告。

新增子命令的说明草案如下；详细参数说明只维护在静态参数契约或对应 skill 附件中，不复制到 Run 顶层 description。实际修改工具整体或参数 description 前，按项目规则确认具体源码文案。

| 子命令 | 说明草案 |
|---|---|
| capture-frame | 从制作节点的视频提取一张关键帧，保存为可继续引用的图片资产和派生节点。 |
| separate-audio | 提取制作节点的音轨并创建派生音频节点。 |
| mute-video | 为制作节点生成无声视频副本及派生节点。 |
| trim-video | 截取制作节点的视频区间并创建派生节点。 |
| derive-view | 基于图片节点调整机位或打光，创建派生图片生成节点并提交任务。 |
| image-preset | 基于图片节点创建带图片预设的派生草稿，供配置和后续生成。 |
| split-grid | 将宫格图片拆成独立资产和分组节点，可对明确选中的格子提交高清任务。 |
| capture-panorama | 从全景图片按指定视角取景并创建派生图片节点。 |

## 节点工具与连续性原则的技能落点

技能按操作契约与制作决策分工，不新增独立 Skill，也不把所有内容加进全局 system prompt。工具未实现前，节点命令只保留在本文；实现并验证后再发布对应运行时附件。

| 文件（相对 assets） | 配套修改 |
|---|---|
| `bundled_skills/screenplay-tools/SKILL.md` | 制作画布的附件路由增加“节点截帧、派生图片、宫格切分与全景取景”；主文件只留入口与用途 |
| `bundled_skills/screenplay-tools/references/production-canvas.md` | 完整维护本节新节点命令的参数、返回、运行等待和“UI 操作对应哪个命令”；区分截图检查、持久资产、生成草稿与生成完成；列出首尾帧节点到下一段 inputs 的操作流程 |
| `bundled_skills/screenplay-tools/references/clips.md` | 维护生成配置与输入绑定的唯一契约；修正“首尾帧与全参考不能混在一组”的笼统限制，说明界面用途与实际发送角色的区别，引用 production-canvas 中的素材派生操作 |
| `official_skills/screenplay-production/references/production.md` | 在“从场次拆分镜”中增加按连续性选择生成边界的决策；区分一次生成内部多个 Shot 与两个独立生成任务，优先把强连续动作留在同一次生成中 |
| `official_skills/screenplay-production/references/model-capabilities.md` | 增加原生首尾帧、普通参考及当前全参考兼容方式的取舍；以真实型号／渠道能力为依据，不将可以提交输入写成同等画面约束保证 |
| `official_skills/screenplay-production/references/image-references.md` | 明确人物／场景／道具参考先用于合成正式关键帧，核对后再送入原生首尾帧模式；正式帧是单张干净画面，不能直接把九宫格拼图当首帧 |
| `official_skills/screenplay-production/references/storyboard.md` | 连续性段落简短引用上述决策；“拆开复杂动作”须说明优先拆成同次生成内的 Shot，跨任务拆分还要满足连续性方案，避免与 production.md 冲突 |
| `bundled_skills/media-editing/references/editing.md` | 保留已经补充的两侧切点比较、关联轨道同步、真实接缝取样和证据边界；这里负责生成后的剪辑检查，不重复生成模式选择规则 |

### 生成前的连续性决策

1. 先判断相邻内容是否要求强连续：同一次动作尚未完成、接触／交接／受力过程、人物精确姿态或空间关系必须紧接时，优先放进同一次生成。一次生成可以包含多个 Shot，不能把换景别等同于必须新建视频生成任务；仍须满足真实时长与动作负载，不能为合并把对白加速或删掉关键过程。
2. 必须跨任务时，先选可信的动作阶段终点、反应或重新交代空间的剪辑边界，再决定输入方式。真正要求边界画面严格接续时评估原生首帧／首尾帧模式，用实际采用结果的尾部状态作为下一段依据；提示词中的计划终点不能冒充已经生成的尾帧。
3. 当前 `productionRoles` 在首尾帧组只发送 first_frame/last_frame；普通参考输入不随该组提交。全参考组允许保留 first_frame/last_frame 用途，但 `productionSubmitRole` 会将它们转换成 reference_image，`compileProductionPrompt` 再追加起止画面的文字指令。这是普通参考加文字约束，不能宣称与原生首尾帧模式具有相同的边界一致性。原生首尾帧也不保证中间过程正确，仍需实际验收。
4. 需要人物、场景与道具依据，又需要原生首尾帧约束时，可先用参考图合成正式关键帧并检查身份、状态与构图，再将确认后的帧作为视频输入。不是要求视频接口同时接收两种互斥输入，也不无条件为每段新增图片生成；已有准确帧直接复用。切换模式须核对实际发送输入、画幅和能力，不能为了通过校验静默丢弃用户期待保留的参考。
5. 需要充分利用全参考输入且不能获得可靠边界约束时，按可独立成立的动作单元和可剪辑边界设计片段；说明接缝需要后期检查与处理，不承诺全参考的用途标签能锁死姿态。生成后回到媒体剪辑技能检查真实接缝。

落地时 bundled 操作附件随实际工具一起更新；official 制片方法可独立交付，但不提前引用未实现的节点命令。修改 official 主文件或附件前核对本地 tags 对应版本；按发布状态处理 version、contentHash、updatedAt，保留版本号时同步 Debug 官方安装快照，保留用户本地副本与安装身份。运行 `bundled_control_skills_test.dart`、`bundled_official_skills_test.dart` 和相关工具合同测试；这些验证加载、指纹与契约，不代表已验证真实模型的连续性效果。

## Write output

保留 `value=文件路径`。只有这两个执行型 output 操作支持下表额外 fields；资源契约显式增加字段操作的 options 声明，`_prepareResourceInput` 按该声明规范化 value 与 fields，`/_schema` 返回完整契约。普通字段 Write 行为不变，不能依靠未知字段被忽略来传执行参数。

| 字段 | 导演 output | 画布 output |
|---|---|---|
| request_id | 必填，格式同生成请求 | 同左 |
| background | 默认 true | 默认 true |
| expected_version | 可选；提供则须等于导演 version | 不适用 |
| camera_id | 可选；默认第一个启用机位 | 不适用 |
| frame | PNG 使用，默认 0；整数，0 至 durationFrames | 不适用 |
| start_frame／end_frame | MP4 使用，默认 0／durationFrames，左闭右开 | 不适用 |
| resolution | 沿保存的导演文档，不覆盖 | 720p／1080p，默认当前剧本设置 |

output 值不增加伪字段；PNG 与 MP4 参数互斥。导演在本次运行内固定当前文档及画幅／fps；画布按场次与片段排序固定当前采用文件。目标只接受 PNG／MP4 对应扩展名，既有文件返回 already_exists，不覆盖。相同会话、动作、目标和 request_id 在本次进程内复用同一 run，参数改变报 conflict；新的输出使用新 request_id 和当前工程。导演不保存输出工程快照、任务恢复文件或帧内容哈希；进程重启不继续旧任务，也不按旧工程补帧。

```json
{"path":"/stagings/staging_1/output","value":"media/exports/shot.png","fields":{"request_id":"still_1","camera_id":"camera_1","frame":24,"background":true}}
```

返回按共用后台合同，最终 result.files 含 file_path、snapshot_path、媒体规格和导演输出的 asset_id。交付失败时保留会话副本并返回实际 snapshot_path 与 delivered=false，可继续按该文件处理，已存在目标不覆盖。控制状态使用 Run operations，不再新增导演／画布专用的轮询命令。

## Run editing

| subcommand | options | 结果 |
|---|---|---|
| list | offset、limit | 工程 id、title、revision、ratio、更新时间，不加载全部文档 |
| create | title、ratio 必填，ratio 为 21:9／16:9／4:3／1:1／3:4／9:16 | 新 id、revision=0、有效空文档；不绑定 episode |
| read | editing_id；track_id 或 start_frame／end_frame 可选 | id、title、revision、fps、ratio、tracks、clips、total_frames；返回的区间仍使用全局帧坐标 |
| apply | editing_id、expected_revision、commands 必填；background=false | 新 revision、每条命令结果、ID 对应及实际影响区间 |
| undo／redo | editing_id、expected_revision | 新 revision 和实际回退范围；历史不可用时 failed_precondition；历史与界面共用，最多缓存 32 个闲置工程、每工程 100 次撤销 |
| preview | editing_id、expected_revision；background=true | 冻结修订的低清连续预览文件及 run_id |
| export | editing_id、expected_revision、output_path、request_id；resolution=720p、subtitles=burn、background=true | 冻结修订的 MP4 及可选 SRT、实际规格、run_id |

subtitles 取 burn／srt／none。read 的帧区间必须同时提供 start_frame、end_frame 且起点小于终点，不能与 track_id 组合产生不明确筛选。apply 命令组最多 100 条、编码后最多 256 KiB，顺序执行，每步经过现有命令校验；整组成功才提交一次文档和修订、形成一次撤销。中间状态不合法也拒绝整组，不能依赖后续命令修补无效状态。

命令使用 op 字段，以下参数均位于命令对象中；新增片段／轨道可提供尚未使用的 id，后续命令可引用该 id，未提供则由应用生成并在 results 返回。现有对象必须使用读取到的真实 ID。

| op | 参数与语义 |
|---|---|
| add_audio_track | id 可选；新增普通音频轨，调用 addAudioTrack |
| update_track | track_id、fields；允许 name／locked／hidden，muted 仅音频轨有效；锁定解除必须是独立的显式命令 |
| reorder_track | track_id、order；同类型非主轨交换顺序，目标锁定时拒绝 |
| remove_track | track_id；主轨不可删，锁定轨不可删，移除轨道及片段不删文件 |
| add_media | id 可选、track_id，file_path／production_clip_id 二选一；主轨用 index，非主轨用 start_frame；来源经探测后保存受控文件引用，不做素材 SHA 校验 |
| add_text | id 可选、track_id、start_frame、text；默认 72 帧，空处长度沿 place 规则 |
| reorder_clip | clip_id、index；仅主轨，按去掉自身后的插入位置重排 |
| move_clip | clip_id、start_frame、track_id 可选；仅非主轨且目标同媒体类型，不自动推动其他片段 |
| trim_clip | clip_id、start_frame、end_frame；使用当前时间线坐标，源入点随首裁切移动；主轨之后重新磁吸 |
| split_clip | clip_id、frame；切点严格位于片段内部，结果返回左右 ID 和源区间 |
| duplicate_clip | clip_id、id 可选；主轨 index／非主轨 start_frame；复制源引用与参数，不复制媒体文件 |
| remove_clip | clip_id；主轨收拢，非主轨保留其他片段位置 |
| update_clip | clip_id、fields；允许 name、scale、opacity、gain_db、fade_in_frames、fade_out_frames、text、text_style、text_position；不接受 x／y、link_group_id 或任意 source 覆盖 |
| replace_source | clip_id、file_path／production_clip_id 二选一；调用 replace，重置源入点，实际时长返回 |
| set_ratio | ratio；校验合法画幅并作为一次可撤销编辑，不跟随剧本继续变化 |
| rename | title；工程名称与 document 在同一 revision 下保存 |

未列出的操作返回 unsupported；未知字段返回 invalid_argument，不静默吞掉拼错的剪辑参数。涉及锁定轨的操作在执行前检查，不能在同一命令组先解锁再绕过已读锁定状态。主轨保持第 0 帧起连续；非主轨 place／replace 的实际缩短必须在 results 中列出。

file_path 可以是已受控路径或用户提供的外部路径；外部输入先经过 files.read，复用导入能力复制进应用媒体目录后再冻结引用。复制失败不提交工程，只清理本次临时副本；不因工程回滚删除已登记业务素材。production_clip_id 解析其当前采用结果并冻结实际文件，不持续跟随之后的采用变化。

```json
{"command":"editing","subcommand":"apply","options":{"editing_id":"editing_1","expected_revision":3,"commands":[{"op":"trim_clip","clip_id":"clip_a","start_frame":24,"end_frame":120},{"op":"update_clip","clip_id":"bgm_a","fields":{"gain_db":-8}}]}}
```

## Run files read

| options 字段 | 合同 |
|---|---|
| path | 必填；可访问的普通绝对文件路径或应用受控相对路径；不支持 Android content URI、目录、通配符或网络 URL |
| mode | auto／text／image／video／audio，默认 auto；显式模式必须匹配探测类型 |
| offset／limit | text 使用，按行，默认 0／200，limit 范围 1 至 1000 |
| continuation | text 超长行续读的应用生成游标，原样传回；与 offset／limit 互斥，仍须传相同 path 并经过 files.read，文件身份改变时 conflict |
| background | 默认 false；异步采用同一 run／通知／取消机制 |

文本本次返回正文最多 64 KiB，按完整行尽量截断，返回 has_more、next_offset 和 truncated；超长单行返回明确截断及该行后续字节游标，调用方通过返回的 continuation 原样续读，不自行混用字节与行号。UTF-8／带 BOM 的 UTF-16 按编码解码，其他编码或二进制返回 unsupported，不用替换字符冒充正确正文。

图片输入最多 32 MiB、解码尺寸最多 64 百万像素；输出缩放长边最多 2048，保持比例，单张编码后最多 3 MiB。超限返回 resource_exhausted 及缩小范围的方法。视频只返回时长、编码、尺寸、帧率等元数据；音频只返回时长、编码、采样率、声道等元数据，不宣称已看过画面、试听或转写。files read 不接受 timestamps_ms，不提供默认或指定时间点抽帧；需要画面时先用 Run ffmpeg 输出图片，再读取图片路径。实际读取、探测及图片解码时限 30 秒，不包含审批与原生任务排队。

结果包含 file_path、kind、mime_type、bytes、可用规格、文本正文及截断与续读信息；图片通过真实 ImageBlock 发送，不把图片字节编码进普通 JSON。聊天历史按顺序保存原文字和图片引用，图片引用只含 file_path、mime_type，不增加资产 ID、视频时间字段或内容哈希。恢复时读取已保存副本；副本不可用只保留路径文字，不报错或中断聊天，由模型判断后续动作。结构与恢复见 [多模态结果与聊天历史恢复](agent.md#多模态结果与聊天历史恢复)。文件读取及音视频元数据探测统一使用已有 files.read 权限 gate，Read 资源返回 file_path 不触发它。副本存于 sessions/{session_id}/，result.content 保存有序文字与图片引用，不新增 AiToolCallBlock 字段。

授权解析一次规范化路径和文件身份，批准后再次核对；相对路径只能落在应用数据目录的受控文件区，绝对路径保持原目标，不像旧媒体路径兼容逻辑那样截取路径片段并重定位。父目录和符号链接解析后的目标也参与校验。目录、设备、命名管道和 URL 明确拒绝。批准前可读取用于展示身份的文件元数据，不能读取正文或解码媒体。

单次批准只覆盖该调用；作用域 allow 覆盖范围内后续文件读取，不要求逐 path 记住授权。外部路径的操作系统访问授权仍由平台处理。文件内容是工具数据，不作为新的系统指令。

## Run ffmpeg

execute／probe 的 options 为 args（必填字符串数组）、request_id（execute 必填，格式同生成）、background（默认 true）；capabilities 无必填参数，返回实际版本、编码器、格式和滤镜。args 最多 256 项、UTF-8 合计 64 KiB，每项不能包含 NUL。不调用 shell，不扩展环境变量、波浪号或 shell 重定向；滤镜里的合法字符按 FFmpeg 语法解析，不当作 shell。

视频抽帧统一由 execute 提供。指定 `-ss` 时间点、`-frames:v 1` 和明确的 PNG／JPG 输出路径，返回生成文件路径、会话副本和真实图片内容；需要再次查看时可调用 Run files read。不向通用 Agent 增加视频时间字段。抽帧时间已在工具调用参数中，相关文字说明作为普通文字保留。

首批兼容范围如下；不在范围内的选项／滤镜在执行前返回 unsupported，说明具体 token，不交给原生库尝试后再判断越权。

| 参数组 | 首批支持 |
|---|---|
| 输入／时段 | `-i`、`-ss`、`-t`、`-to`、`-stream_loop`（0 至 100）、`-loop`（0／1）、`-framerate`、`-f` |
| 流选择／编码 | `-map`、`-an`、`-vn`、`-sn`、`-dn`、`-c`、`-c:v`、`-c:a`、`-codec:v`、`-codec:a`、`-b:v`、`-b:a`、`-crf`、`-preset`、`-pix_fmt`、`-r`、`-s`、`-ar`、`-ac`、`-frames:v`、`-shortest`、`-movflags`；编码器须存在于当前包 |
| 纯处理滤镜 | `-vf`、`-af`、`-filter_complex`；允许 scale、crop、pad、fps、format、setsar、trim、setpts、overlay、concat、split、hflip、vflip、transpose、rotate、eq、volume、atrim、asetpts、amix、afade、aresample、aformat、asplit、anull、null、atempo、color、anullsrc |
| 探测 | probe 只支持 `-show_format`、`-show_streams`、`-show_entries`、`-select_streams`、`-count_frames`、`-of json`／`-print_format json` 和一个文件输入 |
| 能力／日志 | capabilities 执行固定内部查询；execute 可传 `-hide_banner`、`-loglevel`（error／warning／info）、`-n`，宿主补 `-nostdin`，不允许 `-y` |

选项按 FFmpeg 的输入／输出位置归属解析，不能只用正则扫描 `-i`。滤镜图需要解析引号、转义、连接标签、链和滤镜名称，白名单中的滤镜仅接受数值／表达式／流标签／颜色等纯处理参数；拒绝 movie／amovie／subtitles／ass／drawtext／zmq 等会打开额外资源或控制通道的滤镜。字幕烧录由现有 editing export 提供，不在首批原始参数接口里开放任意字体／脚本文件读取。

输入限定当前支持的本地图片、视频、音频格式；`-f` 仅允许实际支持的本地媒体 demuxer／muxer，不接受 lavfi 输入；color／anullsrc 仅可出现在已解析的纯处理 filter_complex 中。首批不开放设备、网络协议、播放清单、concat demuxer 清单、tee／HLS／DASH 等隐式多文件读写。多输入拼接使用显式 `-i` 加 concat filter。输出允许显式指定的 mp4／mov／webm／mkv／png／jpg／webp／wav／mp3／m4a／flac／ogg，按实际编解码器校验；原始参数首批不接受 `%` 序列模板；需要多张帧图时，通过多次 execute 指定不同时间点和图片输出路径，仍沿用同一执行队列及单次输入／输出限额。`-/filter` 文件加载语法、`-filter_script`、`-progress`、`-report`、`-attach` 和任意 URL／协议选项均拒绝。

每个显式输入都匹配 files.read；ask 可将一次调用的全部输入合成一张审批卡。批准后将输入复制或解析为本次可读的受控副本，冻结文件身份；输出先写本次临时目录，校验成功才交付声明路径，输出不能与输入或既有文件相同。网络协议在执行层禁止，不仅依赖模型提示。参数验证不能可靠判定 IO 时拒绝，不能直接透传。

execute 允许最多 8 个输入、4 个明确输出，实际执行默认上限 30 分钟，超时按取消流程停止本地会话并返回 deadline_exceeded 原因，不自动重跑。probe 输出最多 128 KiB，日志返回最后 16 KiB 并标记截断，不返回凭据或无关完整路径。capabilities 反映原生能力，额外返回上面的工具允许范围；原生支持不等于允许透传。

## Codemode 边界

本次不新增 Codemode 的 Run 入口，也不修改 120 秒脚本预算。它继续调用已有 Create／Write／Read 等工具，包括新增的生成及 output 资源动作；权限和后台运行登记由这些工具的共同执行层负责，不能以“在 Codemode 内”跳过审批。

新增长动作默认 background=true，所以 Codemode 得到 run_id 和当前状态后可以返回，审批与执行由会话持有，不把人工等待塞进脚本。显式 background=false 沿原脚本截止时间执行，超时只按真实取消阶段收口，不把已提交生成当作未发生。后续完成通知回到宿主 Agent，由普通工具调用 Run operations／Run files；不要求 Codemode 支持图片输出桥或新 Run 命令。

原 Codemode “仅本地数据工具”的说明需要在实现时精确修正为既有工具集合及其资源能力，不能因为工具名是 Create／Write 就假定它没有异步副作用。此次仅调整这些既有工具的动作分类与结果事实记录，不开放任意网络／shell，description 的具体源码修改仍按确认流程处理。

## 实施与验收

先完成 P-02／C-05 及 episode 自动初始化，保持页面可用；再实现权限与会话后台运行合同、files／providers，随后接生成／输出、Run editing／ffmpeg。每批都复用当前业务服务并独立回归，不等待真实模型调用才能验证调度和取消。

确定性测试必须覆盖：新集创建失败全回滚；旧集首次打开并发只建一份且不读旧字段；主轨删除／裁切／重排磁吸、原声源区间；每个命令的参数和实际返回；后台 waiting_approval／queued／running／取消／终态；cancel 与提交／完成竞争；仅取消等待不终止后台；同 run 通知只消费一次；原会话停止／回退／切换；取消意图重启后不被遗忘；FFmpeg 每类隐式 IO 拒绝；files 内容限额与多模态持久化。真实 Windows／macOS 编码和 Android 权限交互单独验收，Flutter 测试串行。

新增改动位置包括会话后台操作持有者、Run operations handler、生成 cancel_requested_at 及结果应用判断、资源 field options 合同、各命令 handler、工具结果图片消息链路。不得为了任务查询新建持久导出表，也不得把 generation 的上游状态塞进本地 run 状态枚举。

## 工具说明草案

以下仅为新增资源／Run 子命令说明草案；Read／Write／Create 顶层不重复列参数。路径字段和命令 options 的名称、类型、默认值及限制以本文各表生成对应静态契约。

| 入口 | 说明草案 |
|---|---|
| Run production generate-image／generate-video／generate-audio | 按片段已保存的提示词、模型和参考发起一次生成，返回任务身份与状态。重试同一次操作沿用 request_id；重做使用新 request_id。 |
| Write output | 将当前资源的冻结内容输出到指定文件。后台执行返回 run_id，完成或失败后通知；现有文件不覆盖。 |
| Run editing | 读取和编辑指定剪辑，支持磁吸主轨、预览和导出。修改使用读取到的 revision，失败不保留半组命令。 |
| Run files read | 经授权读取指定文件，文本返回正文，图片返回真实内容块；视频和音频只返回元数据，视频抽帧使用 Run ffmpeg。文件无需登记为资产。 |
| Run ffmpeg | 使用受支持的 FFmpeg 参数处理本地素材，返回新文件和实际规格。用 capabilities 查询原生能力及工具允许范围。 |
| Run operations | 查询、等待或取消当前会话的后台操作。等待超时不取消任务；取消请求被接收不代表任务已停止。 |
| background 参数 | 是否后台执行。true 返回运行身份，完成或失败后自动通知；false 等待最终结果。默认值见对应动作。 |

本合同不授权启动付费模型评测；评测仍须单独显式开启。
