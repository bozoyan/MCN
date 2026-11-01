# Markdown 分块虚拟化编辑器

> 状态：已完成架构重构、自动化回归与 macOS Debug 构建验证（2026-08-03）
> 关联代码：`lib/shared/widgets/md/`、`lib/shared/widgets/text_find_replace_scope.dart`

## 1. 背景

旧版 `RevericMarkdownEditor` 用一个全文 `TextField` 渲染 Markdown。约 48 万字符的真实文档会形成一个超高 `RenderEditable/ui.Paragraph`，paint 和 layout 成本随全文长度增长。对照实验中，单个 480k Paragraph 的 paint 约 6.7ms，切为只绘制相交块后约 0.14ms。

第一版分块实现解决了虚拟化，却引入了三套互相竞争的编辑状态：

- 聚焦块 `EditableText.selection`
- 外部全文 `TextEditingController.selection`
- `SelectionArea` 的渲染树选区

`MarkdownBlockController.activateRange()` 还会把跨块范围折叠为起点光标。结果是高亮、输入、删除和焦点分别由不同对象负责，只能通过按键转发和焦点切换勉强同步。

这不是若干独立的边缘问题，而是同一个架构矛盾：编辑器没有唯一的全文编辑值。

## 2. 已出现问题与共同根因

| 现象 | 旧架构原因 |
|---|---|
| 空行过大 | 分隔符、块间距和活动块接管的换行有多个布局所有者 |
| 点击某行后滚到顶部 | `EditableText.showOnScreen`、列表定位和块高校准同时控制滚动 |
| 聚焦前后断行变化 | 未聚焦用 `RenderParagraph`，聚焦用 `RenderEditable` |
| Enter 后光标不进入新行 | 局部块值、全文值与重新切块分阶段发布 |
| 鼠标选中后无法删除 | 高亮属于 `SelectionArea`，删除属于 `EditableText` |
| Backspace 多删一个字符 | key down 期间过户输入焦点，同一个按键被新输入客户端再次消费 |
| Ctrl/Cmd+A 只选当前块 | 默认 `EditableText` 只知道当前块 |
| 全选后点击留下局部反选 | 全文 selection 已折叠，`SelectionArea` 仍保留自己的选区 |
| 上下方向键失效 | 内层 `EditableText` 与外层 `SelectionArea` 的 overridable Actions 发生递归 |
| Cmd+方向键、Ctrl+方向键失效 | 手写 primary-modifier 分支只处理 A/C/X/V/Z/Y，其他组合被截留后无人执行 |
| Cmd+→ 逻辑已到视觉行尾，光标却画在下一行行首 | 软换行两侧共享同一个 offset，自绘光标只传 offset、丢失 `TextAffinity.upstream` |
| 拼音组合串无法退格或移动候选光标 | 编辑器 `Action` 在 composing 期间仍启用并消费按键，平台 IME 收不到 Backspace/方向键 |
| 列表只显示短横或完全没有标记，缩进列表不识别 | 列表前缀被当成可隐藏语法，且正则只接受第 0 列的 marker |
| 拖动滚动条却选中正文 | 祖先原始 `Listener` 也收到 thumb pointer 事件，且不参与手势竞技 |
| 双击、三击仍只得到折叠光标 | 普通 `GestureDetector` 只有单击和 pan 路径，不提供文本编辑所需的连续点击计数 |

运行日志曾稳定出现 Flutter 的 `!_debugAssertMutuallyRecursive` 断言，证明问题不是按键没有送达，而是两层文本 Actions 都在尝试接管同一个 Intent。

## 3. 设计决策

### 3.1 唯一真源

外部 `TextEditingController.value` 是唯一逻辑编辑值，同时原子承载：

```text
TextEditingValue
├─ text            全文 Markdown
├─ selection       全文 UTF-16 坐标
└─ composing       全文 IME 组合区
```

`MarkdownBlockDocument` 只保存由 `text` 派生的块边界和稳定 block id，不拥有第二份文本或 selection。

必须始终成立：

1. 跨块 selection 不降级、不复制到另一个选择对象。
2. 文本、selection、composing 在同一次 `TextEditingValue` 赋值中发布。
3. 分块只影响渲染范围，不改变全文坐标。
4. 所有删除、Enter、粘贴、方向键、撤销都修改同一个值。

### 3.2 编辑器级职责

- 平台输入客户端唯一，输入窗口只是全文逻辑值的投影。
- 鼠标命中直接更新全局 selection。
- 快捷键统一调用同一个 editing controller。
- 只构建可见 Paragraph，绘制时与全局 selection 求交。
- 渲染支持 Markdown 标题、引用等可变字号和可变行高，不能依赖固定行高。

### 3.3 唯一平台输入客户端

`MarkdownTextInputClient` 是整个编辑器唯一的 `DeltaTextInputClient` 和 `TextInputConnection`。

为了避免 48 万字符文档每次方向键都把全文重新发给平台，输入客户端使用“远端输入窗口”：

- 普通输入时只把当前块的可编辑片段发给系统 IME。
- 收到 delta 后映射回全文坐标，再一次性写入唯一 `TextEditingValue`。
- 跨块 selection 时窗口按需扩大到覆盖 selection，因此全选后直接输入仍能替换全文。
- 远端窗口从不向 UI 暴露，也不参与业务状态判断。

长文回归测试会断言：48 万字符文档聚焦普通块后，平台输入窗口仍小于 1000 字符。

### 3.4 单一文本几何

所有块始终使用 `MarkdownReadonlyBlock` 内的 `RenderParagraph`；聚焦时不再换成 `EditableText`。

同一个 Paragraph 同时负责：

- Markdown 富文本与查找高亮
- 全文 selection 与当前块求交后的高亮
- composing 区显示
- 点击/拖选的坐标到全文 offset 映射
- 光标矩形与上下方向键的视觉 x/y 计算

光标由前景 painter 绘制。聚焦不会替换 widget 或 render object，所以普通正文的宽度、断行和高度不再跳变。

所有坐标链路必须传递完整的 `TextPosition(offset + affinity)`，不能退化成裸 offset。软换行处的同一个 UTF-16 offset 有两个视觉位置：`upstream` 是当前视觉行末，`downstream` 是下一视觉行首。光标绘制、行边界查询、鼠标命中、纵向移动和 IME caret rect 都保留 affinity，保证 Cmd+→ 的逻辑 selection 与可见光标一致。

列表标记是不能隐藏的结构信息：`-` / `*` 在活动与非活动行都稳定绘制为 `•`，有序列表保留 `1.` 编号，并支持 Markdown 允许的 0–3 个前导空格。无序 marker 只做等长字形替换，渲染文本与源文的 UTF-16 长度不变，光标、选择和高亮仍共用同一套 offset。

### 3.5 唯一键盘路由

快捷键分成两层，不再由一串 modifier `if` 同时做平台判断和文本编辑：

1. Flutter `DefaultTextEditingShortcuts` 负责把当前平台按键映射为标准 text editing Intent。
2. 列表级 `Actions` 把 Intent 执行到唯一全文 `TextEditingValue`。

`Focus.onKeyEvent` 只保留无 Ctrl/Meta/Alt 的基础字符删除、Enter 和方向键 fallback；有 modifier 的事件必须继续向 `Shortcuts/Actions` 传播。macOS 平台通过 `performSelector` 发来的 selector 也转换为同一组 Intent，不存在第二套执行逻辑。

IME composing 是明确的输入所有权边界：组合区有效时，列表级文本 `Action` 全部禁用，`Focus` 返回 `skipRemainingHandlers`，阻止祖先快捷键继续消费事件，同时把 Backspace、Delete、Enter、方向键及带修饰键的文本操作交还平台输入法。组合提交后才重新启用正文 Action。这样 macOS 拼音和 Windows IME 都能先编辑预编辑串或候选状态，而不会误改正文。

当前桌面快捷键契约：

| 操作 | macOS | Windows / Linux |
|---|---|---|
| 全选/剪切/复制/粘贴 | Cmd+A/X/C/V | Ctrl+A/X/C/V，另支持 Shift+Delete / Ctrl+Insert / Shift+Insert |
| 撤销/重做 | Cmd+Z / Shift+Cmd+Z | Ctrl+Z / Shift+Ctrl+Z / Ctrl+Y |
| 按单词移动或扩选 | Option+←/→，可加 Shift | Ctrl+←/→，可加 Shift |
| 行首/行尾 | Cmd+←/→ | Home/End |
| 文首/文尾 | Cmd+↑/↓ | Ctrl+Home/End |
| 纵向边界 | Option+↑/↓ 到当前视觉行边界 | Ctrl+↑/↓ 到段落边界 |
| 单词删除 | Option+Backspace/Delete | Ctrl+Backspace/Delete |
| 当前视觉行删除 | Cmd+Backspace/Delete | Alt+Backspace/Delete（跟随 Flutter 平台映射） |

上述边界移动都支持 Shift 扩选。行边界来自当前可见 `RenderParagraph` 的实际几何，所以跟随视觉换行；单词边界使用同一 Paragraph 的 Unicode/UAX #29 结果并跳过标点和空格。

删除按 Unicode grapheme boundary 执行，CRLF 和家庭 emoji 不会被拆开。

### 3.6 选择与滚动

桌面鼠标事件由列表级 `TapAndPanGestureRecognizer` 统一接收，并沿用 Flutter 原生文本编辑器的连续点击语义：

- 单击确定全局光标，双击按当前 Paragraph 的 UAX #29 词边界选择文字，三击按全文逻辑换行选择当前段落
- pan start/update 确定全局 anchor 和 extent
- 拖出视口时定时最小滚动，并在新块挂载后继续扩展同一个 selection
- 单击只折叠唯一 selection，不存在需要额外清除的渲染选区
- 滚动条与正文拖选共用 Flutter 手势竞技；命中 thumb 时由滚动条 recognizer 获胜，不会进入正文选择回调

光标滚动也只有一个所有者：列表根据 caret rect 做最小位移。完整可见的点击不会调用顶部对齐。

## 4. 运行时结构

```text
RevericMarkdownEditor                         公开 API 不变
├─ external TextEditingController.value       唯一全文编辑值
├─ MarkdownBlockController                    编辑、IME、selection、undo
│  ├─ MarkdownBlockDocument                   块索引与增量重切
│  └─ MarkdownEditPatchStack                  轻量全文 patch 历史
└─ MarkdownBlockListView                      唯一 Focus、输入与滚动所有者
   ├─ DefaultTextEditingShortcuts / Actions      平台按键意图与全文命令
   ├─ MarkdownTextInputClient                 唯一 TextInputConnection
   ├─ MarkdownBlockMetrics                    高度估算与实测缓存
   └─ SliverList
      └─ MarkdownReadonlyBlock × 可见块       单一 RenderParagraph 几何
```

旧的 `markdown_editing_block.dart` 已删除；编辑器路径中不再存在块级 `EditableText` 或 `SelectionArea`。

`RevericMarkdownPreview` 的只读复制功能仍可使用 `SelectionArea`，它不属于编辑器输入状态。

## 5. 文件职责

| 文件 | 职责 |
|---|---|
| `block/markdown_block_document.dart` | 无损切块、全文 offset 映射、增量重切和稳定 id |
| `block/markdown_block_controller.dart` | 唯一全文值、selection、IME、删除和 undo/redo |
| `block/markdown_text_input_client.dart` | DeltaTextInputClient、局部远端窗口与全文 delta 映射 |
| `block/markdown_block_list_view.dart` | 虚拟列表、快捷键、鼠标选择、上下移动和滚动 |
| `block/markdown_readonly_block.dart` | 富文本、selection、composing、caret 绘制与几何命中 |
| `block/markdown_block_metrics.dart` | 未挂载块高度估算和挂载后校准 |
| `markdown_span_builder.dart` | Markdown span、活动行语法标记和高亮 |

## 6. 外部契约

`RevericMarkdownEditor` 的构造参数和调用方不变：

- 调用方继续持有普通 `TextEditingController` 和 `FocusNode`。
- `.text` 仍可同步读取，外部 AI 写入和自动保存 listener 不需要迁移。
- 外部整篇赋值会增量重建块索引并保留合法 selection。
- `UndoHistoryController` 的按钮入口继续由 `MarkdownEditPatchStack` 驱动。
- `TextFindReplaceScope.ensureRangeVisible` 继续按全文范围定位未挂载块。

## 7. 验证

### 7.1 根因回归（red-green）

新增的“跨块范围保留为全文唯一 selection”测试在旧实现上实际失败：期望 `0..4`，实际得到折叠的 `0..0`。重构后同一测试通过，并继续执行跨块删除。

“拖动桌面滚动条不改变文本选区”测试在原始 `Listener` 路径上也实际失败：滚动成功的同时，全文 selection 从 `0..0` 变为 `13643..13725`。切换为手势竞技后同一测试通过。

“macOS Command 方向键”测试在旧的 primary-modifier 分支上实际失败：按下 Cmd+← 后光标仍停在 offset 6，期望值为当前行首 offset 4。改为平台 Intent 路由后同一测试通过。

“Cmd+→ 的可见光标位于当前视觉行末”测试进一步确认：逻辑 selection 已是软换行 offset 且 affinity 为 `upstream`，但旧自绘链路按默认 `downstream` 计算，caret 中心 y 为 58.25，落在下一视觉行顶部 51.5 之后。全链路保留 `TextPosition.affinity` 后，同一 offset 稳定绘制在上一视觉行末。

“IME 组合态退格”测试在未隔离 composing 的 Action 层上实际失败：Backspace 被 Flutter 返回为已处理，正文虽未变化，平台输入法却收不到按键。把组合态按键显式交还平台后，macOS 与 Windows 的 Backspace/方向键均返回未处理；提交后 Backspace 恢复为编辑器处理并删除正文。

“段落后的缩进列表”测试在旧解析器上实际失败：期望两个可见 `•` 前缀，实际为 0；有序列表同样没有产生可见编号 span。分离源前缀与渲染前缀后，无序列表稳定显示项目符号，有序列表保留编号。

“桌面双击/三击选择”测试在普通 `GestureDetector` 路径上实际失败：双击 `alpha` 得到空选区，三击后 selection 仍折叠在 offset 6。改用带连续点击计数的 `TapAndPanGestureRecognizer` 后，双击选中命中单词，三击选中含结尾换行的当前逻辑段落。

### 7.2 自动化覆盖

`test/shared/widgets/md/block/markdown_block_controller_test.dart`：

- 跨块 selection 与一次删除
- Enter 与后续输入的全文光标
- IME composing/commit 和单步撤销
- CRLF、emoji grapheme 删除
- 外部整篇写入、undo/redo

`test/shared/widgets/md/markdown_block_editor_test.dart`：

- 一个空行的段落间距
- 聚焦前后同一个 RenderParagraph、相同视觉断行
- 点击完整可见块不改变 scroll offset
- 拖动桌面滚动条只滚动视口，不改变文本 selection
- Enter 后可见光标进入下一行
- 同块/跨块鼠标选择、复制和 Backspace
- 桌面双击选择 Unicode 单词、三击选择当前逻辑段落
- Ctrl/Cmd+A → 点击 → 再全选 → 输入替换 → 删除
- 上下方向键按视觉行移动、跨过段落空行，且无 Actions 递归异常
- macOS Cmd+方向键的视觉行/全文边界、软换行处的可见 caret affinity、Shift 扩选、Option 单词移动与删除
- Windows Ctrl+单词/段落、Home/End、Ctrl+Home/End、Shift 扩选、Ctrl+Y 重做
- Windows CUA 的 Shift+Delete / Ctrl+Insert / Shift+Insert 剪切复制粘贴
- IME 输入不挂载隐藏 `EditableText`，macOS/Windows 组合态退格与方向键交还平台
- 段落后的缩进无序/有序列表，项目符号和编号在聚焦前后持续可见
- 48 万字符/3600 块只挂载 `<20` 个块
- 长文普通输入窗口 `<1000` 字符
- 拖选边缘自动滚动和文末查找定位

同时串行验证：

- `markdown_block_document_test.dart`：18 个测试，含 600 步随机编辑 property 测试
- `markdown_edit_patch_stack_test.dart`：11 个测试
- Markdown span/preview：7 个测试
- `text_find_replace_scope_test.dart`
- 桌面 workspace entry/compact layout
- 移动 entry editor layout
- agent rule editor layout

### 7.3 静态与运行时验证

- `fvm flutter analyze lib/shared/widgets/md test/shared/widgets/md`：通过，无问题。
- `fvm flutter test test/shared/widgets/md/markdown_block_editor_test.dart`：20 个 Widget 回归通过（含桌面连续点击、macOS/Windows 平台键位与 IME 组合态覆盖）。
- `fvm flutter test --concurrency=1 test/shared/widgets/md`：与 Markdown 编辑器相关的 66 个测试全部通过。
- `fvm flutter build macos --debug`：成功生成 `build/macos/Build/Products/Debug/Reveric.app`。
- 全仓库 `fvm flutter analyze` 仍报告 187 个既有 warning/info，本次 Markdown 编辑器改动路径不在其中。

### 7.4 验证边界

Widget 测试验证结构性虚拟化和事件序列，不等价于真实 GPU profile。真实 paint 基线仍需在 release/profile 包中用 DevTools 复测；IME 候选窗位置和移动端长按选择也应保留真机发布前检查。

Windows 快捷键已通过 `TargetPlatform.windows` Widget 事件序列验证，当前 macOS 开发环境无法等价替代 Windows 真机的系统 IME、键盘布局与无障碍联调，发布前仍需一次 Windows 实机 smoke test。

## 8. 剩余风险

| 风险 | 状态 |
|---|---|
| 未挂载块的高度估算转实测时可能产生小幅校准 | 保留现有三次估算/几何校正；不影响点击时的可见块滚动 |
| 跨块 selection 很大时平台输入窗口也会扩大 | 只有选择后直接输入需要；普通方向键和输入保持块级窗口 |
| 移动端原生选择手柄/工具栏 | 当前保留点击输入和 IME；需要独立补齐原生手柄体验 |
| 含空行的搜索词跨多个块 | 查找范围能定位，但多块高亮仍是低优先级缺口 |
| 章节正文的另外两个专用 TextField | 不在本方案范围，仍有同类长文本性能风险 |

## 9. 完成定义

- 编辑器只有一个逻辑 `TextEditingValue`、一个 Focus 和一个 TextInputConnection。
- 编辑路径无 `SelectionArea`、无块级 `EditableText`、无焦点过户。
- 用户已报告的间距、跳顶、断行、Enter、删除、全选、方向键、双击/三击选择、软换行 affinity 和列表标记均有回归测试。
- 长文继续按视口虚拟化，输入通道不因普通光标移动发送全文。
- 临时输入探针日志与旧编辑块实现已清理。
