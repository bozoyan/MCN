# 技能广场方案

日期：2026-10-30。状态：方案已更新，尚未实施。本次交付是文档，不包含创建远端仓库、收录内容或修改客户端。

## 1. 目标与范围

创建独立公开仓库 `looplj/reveric-skills`，用一个 `catalog.json` 收录技能名称、简介、适用场景和来源链接，用 `skills/` 存放自己维护的技能。Reveric 读取目录展示技能广场，用户点击条目到原站查看说明，需要使用时通过现有仓库导入功能导入。

GitHub 是目录托管位置，技能来源不局限于 GitHub。GitHub、GitLab、Gitee、GitCode 的公开仓库链接沿用现有导入能力；其他公开 HTTPS 链接可以作为推荐资源展示和打开，不承诺直接导入。

README 提供技能表格，由 `catalog.json` 自动生成。目录文件是唯一维护的数据源，客户端和 README 使用同一份信息。

首版包含列表、搜索、分类筛选、打开来源、预填链接导入和目录缓存。成功标准是用户能从广场找到技能、打开作者说明，并复用现有流程完成导入；Windows、macOS、Android 行为一致。

首版不做应用内技能详情页、远端版本管理、自动升级、评论、评分、排行榜或专用后台。没有 `entries/`、安装清单、固定 commit 要求、额外文件哈希、目录发布标签或目录生成流程。README 表格生成是唯一新增的生成步骤。

## 2. 当前实现与复用边界

| 当前能力 | 代码位置 | 本次处理 |
| --- | --- | --- |
| 桌面市场占位 | `lib/desktop/features/agent_skills/marketplace_catalog_tab.dart` | 替换为链接目录 |
| 移动端市场占位组件 | `lib/mobile/features/agent_skills/marketplace_tab.dart` | 替换为链接目录，并挂入全局技能页 |
| 移动端全局技能页 | `lib/mobile/features/agent_skills/global_skill_setup_page.dart` | 当前只有已安装、官方两个标签，新增广场标签与内容 |
| 链接解析和下载 | `agent_skill_import_source.dart`、`agent_skill_import_orchestrator.dart` | 沿用支持的平台、链接格式和下载规则 |
| 导入来源表单 | `lib/shared/widgets/agent_skill_import_source_form.dart` | 增加可选 `initialUrl`，预填用户点击的链接 |
| 桌面导入流程 | `lib/desktop/features/agent_skills/setup_panel.dart` | 原有导入入口接受可选初始链接 |
| 移动端导入流程 | `lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart` | 提取现有导入函数供已安装页和广场共用 |
| 本地快照和历史 | 现有 InstalledAgentSkillsNotifier 与 DAO | 继续按普通导入写入本地技能 |
| 本地官方目录 | `lib/shared/services/agent_skill_catalog_service.dart` | 保持原行为，增加独立的广场列表读取方法 |

仓库链接可以指向一个技能目录，也可以指向包含多个技能的项目。广场条目不与本地技能建立一对一安装关系，不根据条目名称判断是否已安装，不显示版本或升级标记。

现有导入负责扫描候选、名称冲突、附件限制、下载取消和保存结果。广场只把链接交给它，不增加另一套安装流程。导入后的来源保持 `novelLocal`，不写 `marketplace` 来源或新增追溯字段。

## 3. 独立仓库

```text
reveric-skills/
  README.md
  CONTRIBUTING.md
  LICENSE
  catalog.json
  skills/
    <skill-name>/
      SKILL.md
      references/
  tool/
    update_readme.dart
```

第三方项目只收录链接，内容继续由原作者维护。原创技能放在 `skills/`；改编内容按原许可保留必要的 LICENSE、署名和上游说明。仓库内置技能也按需导入，不意味着随应用打包。

现有 `assets/bundled_skills/`、`assets/official_skills/` 的归属、版本和同步机制不变。本次不迁移打包技能，也不把远端目录当作本地官方目录的替代来源。

README 手写项目介绍、贡献方式和导入说明；技能表格由工具维护。CONTRIBUTING 说明如何修改目录、运行表格生成，以及新增原创技能时如何组织文件。不要求搭建 CI、CODEOWNERS 或多阶段发布流程。

### 收录与更新

1. 维护者或投稿者直接修改 `catalog.json`，填写名称、简短用途和来源链接，建议补充 `when_to_use` 说明适用场景；分类、标签按需要填写。
2. 原创技能可以与目录条目在同一个 PR 提交，链接指向合并后的主分支目录，无需拆成两次提交获取 commit。
3. 检查链接可打开、介绍与原站一致。需要支持导入的链接，用现有导入入口试一次；不在目录中重复登记文件清单和测试记录。
4. 运行 README 表格生成与一致性检查，将目录和表格变更一起提交。
5. 维护者确认后合入 `main`，客户端刷新即可读取。修改介绍或链接直接编辑原条目；移除推荐直接从目录删除条目。

删除目录条目只影响后续展示，不删除或停用已导入的本地技能。历史目录通过 Git 提交记录查看。

## 4. catalog.json 格式

顶层为 JSON 数组，每个元素是一条推荐记录。数组顺序就是默认展示顺序，不另设排序字段。

| 字段 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 展示名称，非空字符串 |
| `description` | 是 | 简短用途说明，非空字符串 |
| `when_to_use` | 否，建议填写 | 适用场景，说明什么任务、对象或阶段适合使用；缺失或空字符串时不展示场景说明 |
| `url` | 是 | 来源页面的绝对 HTTPS 链接，非空且不能包含用户名、密码 |
| `category` | 否 | 分类字符串，未填写表示不分类 |
| `tags` | 否 | 字符串数组，未填写按空数组处理 |

`description` 回答“能做什么”，`when_to_use` 回答“什么时候用”。比如简介是“检查剧情连续性”，适用场景可以是“完成章节初稿后，检查人物状态与前文设定是否矛盾”。使用与现有技能格式一致的 `when_to_use` 字段名，不另造同义字段。

目录中的 `when_to_use` 帮助用户选择技能，不作为运行时触发提示写入本地。导入仍由现有解析器读取 `SKILL.md` 的 `when_to_use`；技能文件未提供时沿用现有的 `description` 回退规则，不用目录说明覆盖作者内容。收录整个技能集合时，目录适用场景描述集合用途，不套用到每个导入候选。

名称、简介和适用场景作为收录内容原样展示，不要求每条提供多语言版本。按钮、页面标题和状态提示仍使用应用现有 i18n。分类候选由目录中实际出现的非空分类去重得出，标签用于展示和搜索。

以去掉首尾空白后的完整 URL 检查重复，保留 URL 的路径、query 和 fragment 语义，不按名称合并不同项目。重复 URL、无效字段类型或非法链接导致目录校验失败；空数组是合法空目录。未知附加字段忽略。

首版不引入条目 ID、作者重复资料、版本号、更新时间或审核人字段。作者、许可、详细介绍和示例由原站提供。链接可以跟随分支更新，不要求固定到某次提交；现有导入器下载时怎样解析链接，继续按其现有行为执行。

目录入口常量为 `https://raw.githubusercontent.com/looplj/reveric-skills/main/catalog.json`，存入 `lib/shared/app_config.dart`。这是拟创建仓库的目标地址，当前没有完成在线验收。

## 5. README 表格生成

`tool/update_readme.dart` 使用 Dart 标准库读取目录并生成 Markdown，不需要 Flutter 或额外依赖。在独立技能仓库根目录执行：

```bash
dart run tool/update_readme.dart
dart run tool/update_readme.dart --check
```

第一条命令更新 README 指定区域；第二条只检查，内容不一致或目录非法时返回非零退出码，不写文件。

生成区域使用两个固定标记：

```markdown
<!-- skills-table:start -->
<!-- skills-table:end -->
```

两标记之间生成“技能、简介、分类、标签”四列表格，README 不展示 `when_to_use`。“技能”列显示名称并链接到 `url`，可直接从 GitHub README 打开原站。缺少分类或标签时显示“无”；空目录只生成表头，不插入虚构条目。

生成规则如下：

- 严格沿用目录数组顺序，重复运行结果一致，不插入生成时间。
- 正确转义单元格中的竖线、换行、HTML 与 Markdown 控制字符，标签以顿号连接，链接地址作适当编码，避免破坏表格或改变目标 URL。
- 只替换标记内内容，保留 README 其余说明。标记缺失、顺序错误或出现多组时明确报错，不猜测替换位置。
- 目录校验通过后才写 README；读写失败不截断原文件。

`catalog.json` 由人维护，README 表格由工具生成。工具不反向解析 README，也不生成或重写目录文件。

## 6. 客户端交互与数据流

```text
catalog.json -> 目录读取与缓存 -> 共享列表状态 -> 桌面 / 移动广场
                                                  |
                                      +-----------+-----------+
                                      |                       |
                                  打开原站                预填链接导入
                                      |                       |
                                  系统浏览器              现有导入流程
```

列表展示名称、简介、适用场景、分类、标签和来源主机名，未填写适用场景时隐藏对应说明。点击名称或卡片打开来源链接，不进入应用内详情页，也不抓取原站内容。用户在浏览器中查看作者的说明、示例和要求。

对 `AgentSkillImportSource.parse(url)` 接受的链接显示“导入”动作，点击后打开现有导入弹窗或移动 sheet，自动填好链接。用户按现有流程触发扫描、选择候选、确认导入，打开弹窗本身不开始下载。无法被当前解析器接受的 HTTPS 页面保留浏览能力，不显示导入动作；不为这些页面新增抓取器。

导入后继续使用已有的成功、部分失败、同名跳过等反馈；再次导入也沿用现有冲突处理，不提供广场专属的覆盖或升级功能。用户已经导入的技能可照常编辑、停用和使用。

### 目录加载

- 第一次进入广场时读取缓存并发起一次目录请求；有缓存先显示缓存，收到有效响应后替换列表。同一会话切换标签、搜索和分类不重复联网，用户可手动刷新。
- 将最近一次成功的目录保存在应用支持目录下 `skill_marketplace/catalog.json`，读取时同样校验。只保留这一份目录，不建立条目详情或安装包缓存。
- 下载超时或解析失败时，有有效缓存就保留并提示刷新失败；无缓存则展示错误和重试入口。合法空数组显示空目录，搜索无结果单独显示筛选状态。
- 目录接收大小上限为 2 MiB，连接超时 10 秒、接收超时 30 秒；在接收过程中限制字节数。缓存采用临时文件写入后替换，写缓存失败时当次有效内存列表仍可使用，并记录诊断。
- 搜索名称、简介、适用场景、分类和标签，在内存过滤。刷新只影响目录，不触发任何技能下载或数据库写入。

目录故障不阻止用户使用已显示的来源链接或现有导入入口。新导入需要来源平台可访问；导入后使用本地快照不依赖目录服务。

### 跨平台与文案

桌面复用现有市场标签页，移动全局技能页增加广场标签并挂载已有市场组件。两端使用相同数据和链接行为，移动端返回时沿用现有导入取消逻辑。

若调整桌面页头，操作区单独避让 Windows 窗口按钮，保持标题顶部基线，并覆盖 macOS、Linux 布局分支；Android 验证窄屏列表、长标题、搜索键盘和返回操作。通用按钮优先复用 `common.*`，广场状态文案放在 `agent_skill` 命名空间，同步中英文。

## 7. 文件级改动

实现涉及共享目录、两个平台入口和测试，预计超过 8 个文件。复用现有 Service、导入器和数据库，不新增安装 Orchestrator。

| 文件 | 改动 |
| --- | --- |
| 新建 `lib/shared/models/marketplace_agent_skill.dart` | 定义六字段目录条目和严格 JSON 校验，`when_to_use` 映射为可选 `whenToUse`；不增加安装版本模型 |
| `lib/shared/services/agent_skill_catalog_service.dart` | 新增 `listMarketplace` 和目录缓存读取，注入 HTTP、缓存目录依赖；官方本地读取保持独立 |
| `lib/shared/providers/agent_skill_catalog_providers.dart` | 增加广场目录加载、刷新和内存筛选状态，与官方目录状态分开 |
| `lib/shared/app_config.dart` | 增加目录 URL 常量 |
| `lib/desktop/features/agent_skills/marketplace_catalog_tab.dart` | 列表、搜索、分类、打开来源，接收导入回调 |
| `lib/desktop/features/agent_skills/setup_panel.dart` | `selectSkillsForImport`、`importInstalledSkills` 接受可选初始链接，并将回调传入广场 |
| `lib/mobile/features/agent_skills/marketplace_tab.dart` | 与桌面一致的列表和动作，调用移动端导入入口 |
| `lib/mobile/features/agent_skills/global_skill_setup_page.dart` | 同步修改 TabController 数量、TabBar 和 TabBarView，挂载广场 |
| 新建 `lib/mobile/features/agent_skills/import_flow.dart` | 从已安装页提取既有 `_importSkills` 流程，提供接受可选初始链接的页面级函数 |
| `lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart` | 调用提取后的导入函数，保留原行为，不复制第二套流程 |
| `lib/shared/widgets/agent_skill_import_source_form.dart` | 可选 `initialUrl` 初始化输入框，不自动扫描；默认空值兼容现有调用方 |
| `lib/shared/localization/locale_keys.dart`、`assets/translations/en/agent_skill.json`、`assets/translations/zh-CN/agent_skill.json` | 广场标题与加载、刷新、打开失败状态文案 |

新建模型、移动导入函数文件时遵循项目路径和文件头规则。实现前读取对应代码风格、目录结构、状态管理、Hooks、输入法、设计系统、文件访问、i18n、错误处理与测试规则；修改桌面页头时额外读取窗口规则。本方案不产出 mockup。

不修改 DAO、Drift schema、来源枚举、打包技能或既有技能历史结构；无需 migration，也不为目录移除编写本地数据清理逻辑。现有导入器中的路径校验、大小限制等继续保留，省去的是额外的广场清单协议。

## 8. 验证与验收

| 场景 | 通过标准 |
| --- | --- |
| 目录解析 | 必填字段、类型、HTTPS 链接和重复 URL 正确校验，合法空数组可用 |
| 适用场景 | 有值时在桌面和移动端展示且可搜索，README 不展示；缺失或为空仍可收录；导入结果使用技能文件中的触发说明，不受目录文案影响 |
| 列表交互 | 顺序与目录一致，搜索分类在本地执行，点击来源传递原始 URL，不发起详情请求 |
| 多来源 | 四个平台的受支持链接进入既有导入；普通 HTTPS 页面可打开且不出现错误导入入口 |
| 预填导入 | 两端打开导入表单后链接正确，未确认扫描前不下载，取消后不写数据 |
| 导入回归 | 候选选择、同名跳过、附件、失败反馈与原手动粘贴导入一致 |
| 移动入口 | 三个标签与内容一一对应，广场可达，原两个标签行为不变 |
| 缓存与失败 | 无网有缓存仍可浏览；坏响应不覆盖好缓存；首次失败可重试；浏览器打开失败有反馈 |
| README 生成 | 表格与目录一致、顺序稳定、特殊字符不破坏格式、重复运行无差异、标记外内容不变 |
| README 检查 | `--check` 对一致结果成功；修改表格使用的字段后未重新生成则失败，且不修改 README；仅修改 `when_to_use` 不改变表格结果 |
| 本地数据 | 移除目录条目、刷新目录和打开来源均不改变已导入技能或官方同步结果 |

新增 `test/shared/models/marketplace_agent_skill_test.dart`，扩展既有目录 Service、目录 Provider、导入表单、两端市场和全局技能页测试。网络及浏览器打开使用注入的替身，不访问真实外站。涉及真实翻译的 Widget 测试在 setUp 清理 `rootBundle` 缓存，监听 Drift stream 的测试结束后拆树并 settle。

实现后串行运行以下命令，测试路径包含本方案要求新增的文件，当前不能视为已执行：

```bash
fvm flutter test test/shared/models/marketplace_agent_skill_test.dart test/shared/services/agent_skill_catalog_service_test.dart test/shared/providers/agent_skill_catalog_providers_test.dart
fvm flutter test test/shared/services/agent_skill_import_source_test.dart test/shared/services/agent_skill_import_orchestrator_test.dart
timeout 180s fvm flutter test test/shared/widgets/agent_skill_import_source_form_test.dart
timeout 180s fvm flutter test test/desktop/features/agent_skills
timeout 180s fvm flutter test test/mobile/features/agent_skills test/mobile/pages/novel_agent_skill_manage_page_test.dart
fvm flutter analyze lib/shared/models/marketplace_agent_skill.dart lib/shared/services/agent_skill_catalog_service.dart lib/shared/providers/agent_skill_catalog_providers.dart lib/shared/widgets/agent_skill_import_source_form.dart lib/desktop/features/agent_skills lib/mobile/features/agent_skills
```

移动全局技能页新增测试放在 `test/mobile/features/agent_skills/global_skill_setup_page_test.dart`，由上面的目录测试覆盖。环境没有 `timeout` 时先提供等效的超时包装，不能无期限等待 Widget 测试。

README 工具在独立仓库运行生成和 `--check`；用临时目录里的样例验证竖线、换行、链接括号、重复 URL、空数组和错误标记，确认检查失败不写文件。Windows、macOS、Android 各手动完成打开来源与导入；四种代码托管来源分别验证一次，不能把链接能解析当作远端一定可下载。

本方案不增加模型调用或提示词内容，不设置额外的 AI 评测流程；收录介绍不能把未经验证的兼容性或效果写成保证。

## 9. 发布、回滚与维护

### 独立仓库交付

- [ ] 创建仓库，编写说明与贡献方式，维护真实的 `catalog.json`，按需加入自有技能。
- [ ] 实现 README 表格工具，检查正常生成、特殊字符和 `--check` 行为。
- [ ] 合入后从未登录环境验证目录地址、README 表格链接和实际导入来源。

仓库可以先独立使用：用户从 README 找到资源，直接打开来源或复制链接到已有导入入口，不依赖客户端广场先上线。

### 客户端交付

- [ ] 接通目录加载、缓存、列表和来源打开。
- [ ] 桌面和移动端预填导入接线完成，移动广场入口实际可达。
- [ ] 完成受影响测试及三平台手工验收，再发布客户端。

维护者修改目录时运行表格生成并一起提交即可。错误收录直接修正或移除；目录修复后用户刷新获得新列表。若需客户端回退，恢复原入口状态，已导入技能仍是本地快照，无需数据库回滚。

### 成本与观察

浏览只请求一个目录文件，搜索和分类不联网；原站内容由浏览器按用户操作访问。导入成本与当前粘贴链接导入相同，不额外请求详情、清单或逐条上游元数据。README 工具仅做本地 JSON 和文本处理，不调用模型。

首发用受控样本记录“条目能打开、支持的链接能导入、导入后能使用”三个结果，失败时区分目录错误、来源失效和现有导入错误。维护者收到失效反馈后复核链接并修正目录；不新增业务埋点、后台看板或全站可用性扫描。当前没有全量用户统计，不能据此判断真实转化率或留存。

接受的限制是原站内容和分支可能变化、链接可能失效、浏览器访问与导入都依赖相应网络。目录托管需要 GitHub 可达，但其他平台来源继续使用自身下载路径。客户端无需 GitHub 账号或新增凭证；维护者用现有 GitHub 账号管理目录仓库。
