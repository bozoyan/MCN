# Prompt Regression Evaluation 方案

## 背景

Reveric 的 Agent prompt 已经集中到 `assets/prompts/agent/*.md` 和 `PromptRegistry`，但 prompt 修改后缺少不启动 UI 的真实模型回归手段。目标是提供一个开发期工具：直接运行固定场景，评估 agent persona prompt 的行为是否仍符合预期，并为后续 prompt 优化提供证据。

本方案覆盖第一版 Prompt Regression Evaluation，并已实现多维打分、多轮统计和回归对比。完整 tool-enabled workflow 评估预留结构，但不在第一版实现。

## Flutter 版本兼容

Flutter 3.44+ 的 `flutter pub run` 无法加载 `dart:ui` 库（仅 Flutter engine 运行时可用），而 `run_agent_eval.dart` 通过 `package:reveric` 间接依赖 `package:flutter` → `dart:ui`。

因此评测必须通过 `flutter test` 运行——`flutter test` 会初始化 Flutter engine，`dart:ui` 可用。入口封装在 `test/tool/evaluation/run_eval_integration_test.dart`，通过 `EVAL_ARGS` 环境变量传递 CLI 参数。

详见「运行命令」一节。

## 目标

1. 不启动 UI，直接从命令行运行真实模型评测。
2. 第一版只评估内置 agent persona prompt 的输出质量。
3. 同时使用确定性规则和独立 Judge Agent 判定结果。
4. 输出机器可读报告和人类可读摘要。
5. 不修改 app 数据库、不自动优化 prompt、不提交运行结果。

## 非目标

1. 不做用户可见功能。
2. 不进入默认 `dart test` / CI 单元测试链路。
3. 不覆盖 write/edit/read tool workflow。
4. 不保存 golden baseline 做逐字 diff。
5. 不自动修改 `assets/prompts/**`。

## 放置位置

开发工具放在 `tool/evaluation/`，不放在 `lib/shared/services/ai/evaluation/`。

原因：

- 这是开发期 prompt 回归工具，不是 app runtime 能力。
- runner 需要文件系统、真实模型配置、fixture、报告输出，放入 `lib/` 容易污染产品边界。
- `lib/shared/services/ai` 只复用现有 Agent runtime、ProviderClient、PromptRegistry 等能力。

建议目录：

```text
tool/evaluation/
  run_agent_eval.dart
  scenarios/
    prompt_regression/
      writer-keeps-user-intent.json
  fixtures/
    writer-intent-source.md
  results/
    .gitkeep
```

`tool/evaluation/results/` 是本地输出目录，不提交运行结果。

## 运行命令

> **注意**：由于 Flutter 3.44+ 中 `flutter pub run` 不支持 `dart:ui` 导入，评测必须通过 `flutter test` 运行。  
> 详见 `docs/solutions/prompt-regression-evaluation.md` 的「Flutter 版本兼容」一节。

支持按 scenario id 和 prompt id 过滤，支持独立 Judge 模型和回归对比：

```bash
# 通过 flutter test + EVAL_ARGS 环境变量传递参数
EVAL_ARGS="--scenario review-finds-concrete-issues" flutter test test/tool/evaluation/run_eval_integration_test.dart

EVAL_ARGS="--prompt-id agent.writer" flutter test test/tool/evaluation/run_eval_integration_test.dart

EVAL_ARGS="--yes" flutter test test/tool/evaluation/run_eval_integration_test.dart

# 使用更强的模型做独立 Judge
EVAL_ARGS="--yes --judge-model openai::gpt-4o" flutter test test/tool/evaluation/run_eval_integration_test.dart

# 与基线报告进行回归对比
EVAL_ARGS="--yes --compare tool/evaluation/results/baseline.jsonl" flutter test test/tool/evaluation/run_eval_integration_test.dart
```

如果未来 Flutter 恢复 `flutter pub run` 对 `dart:ui` 的支持，也可直接使用：

```bash
flutter pub run tool/evaluation/run_agent_eval.dart --scenario review-finds-concrete-issues
```

默认确认策略：

- `--scenario` 匹配单个 case：直接执行。
- `--prompt-id` 匹配多个 case：打印 provider、model、case 数量后交互确认。
- 无过滤全量运行：必须加 `--yes`，否则只打印将要运行的清单并以配置错误退出。

## 被测对象

第一版使用 `prompt_id` 作为被测对象标识，不使用 `agent_slug`。

原因：

- 当前目标是 prompt 回归，不是数据库 agent 配置回归。
- `PromptRegistry` 中的 `PromptId.agentWriter` 等 ID 比数据库 slug 更稳定。
- runner 可以通过 `prompt_id` 找到 `assets/prompts/agent/*.md`，渲染 system prompt 后构造 `Agent.custom()`。

第一版运行方式：

- `allowedTools: []`
- `maxIterations: 1`
- 使用真实 `ProviderClient`
- 使用全局默认 chat model

后续 Full Agent Workflow Evaluation 再引入 `agent_slug`、工具权限、自定义 prompt、技能引用和副作用评估。

## 模型与配置

runner 使用 app 当前真实 AI 配置：

1. 默认读取真实本地 app 数据库。
2. 支持 `--database` 覆盖数据库路径。
3. 启动时打印实际数据库路径、provider id、model、temperature、maxTokens、reasoningEffort。
4. 使用全局默认 chat model，不使用 role-specific model。
5. 采样参数直接使用 provider 当前配置，不覆盖 temperature。

只读原则：

- 不允许触发数据库迁移。
- 不允许初始化默认 provider。
- 不允许写入 app settings。
- 数据库不存在、schema 不匹配、`ai_providers` 为空、默认 chat model 缺失时直接失败。
- 如果 `defaultChatModelId` 缺失，即使存在 enabled provider，也不 fallback 到第一个可用 model。

## Prompt 加载

CLI 不使用 `PromptTemplateService.loadAll()`，因为它依赖 Flutter `rootBundle`。

第一版新增文件系统 loader，直接从工作区读取 `assets/prompts/**.md`：

- 复用 `PromptRegistry` 的 prompt id 和 template path。
- 语义贴近 `PromptTemplateService` 的 `rawAsset()` / `renderAsset()`。
- 使用当前工作区文件内容，确保评测的是未打包的最新 prompt 修改。

## Scenario 格式

scenario 使用 JSON。每个文件只包含一个 case，方便单独运行和 git diff。

示例：

```json
{
  "id": "writer-keeps-user-intent",
  "prompt_id": "agent.writer",
  "input": "把这一段扩写成更有张力的场景：……",
  "must_include": ["张力"],
  "must_not_include": ["作为一个AI"],
  "rubric": "评估是否保留用户意图、扩写具体、没有越界添加无关设定。",
  "min_score": 4,
  "runs": 1,
  "tags": ["writer", "intent"],
  "notes": "防止 writer 在扩写时改写用户核心意图。"
}
```

长输入可以用 `input_file`：

```json
{
  "id": "writer-long-scene-keeps-intent",
  "prompt_id": "agent.writer",
  "input_file": "tool/evaluation/fixtures/writer-long-scene.md",
  "rubric": "评估是否保留原场景目标，并扩写为可直接使用的小说正文。",
  "min_score": 4
}
```

规则：

- `input` 和 `input_file` 必须二选一。
- 每个 scenario 只测试一个核心行为。
- `must_include` / `must_not_include` 是硬性规则，支持普通字符串和正则（`/pattern/` 包裹）。
- `rubric` 聚焦该 case 的单一回归风险。
- 默认 `runs: 3`，支持多轮统计（mean、stddev、min/max、pass rate）。
- `dimensions`: 可选多维评分维度数组，每项含 `name`、`weight`（权重和须 = 1.0）、`rubric`。不指定则默认单一「综合」维度。

为后续 Full Agent Workflow Evaluation 预留字段：

```json
{
  "allowed_tools": [],
  "initial_state": {},
  "expected_tool_calls": [],
  "forbidden_tool_calls": [],
  "expected_artifacts": []
}
```

第一版不实现这些字段的行为，只保留 schema 扩展方向。

## 判定机制

判定分两层。

第一层是确定性规则：

- 检查 `must_include`。
- 检查 `must_not_include`。
- 硬规则失败时 case 直接失败。

第二层是 Judge Agent：

- Judge Agent 必须是独立 agent，不能使用被测 agent 的自检。
- 不复用 `VerificationHook`。
- Judge Agent 也必须通过 `Agent.custom()` 运行，遵守 AI 调用规则。
- Judge 输出必须是严格 JSON，不能解析则视为运行时错误。

Judge JSON 建议格式：

```json
{
  "score": 4,
  "passed": true,
  "reasons": ["保留了用户意图", "输出可直接作为正文使用"],
  "violations": [],
  "suggestions": ["可以在 writer prompt 中更明确要求避免新增无关设定"]
}
```

runner 仍然要检查 `score >= min_score`，不能只相信 `passed`。

## 报告输出

每次运行生成两类输出。

机器可读报告：

```text
tool/evaluation/results/<timestamp>.jsonl
```

每个 scenario 一行，至少包含：

- scenario id
- prompt id
- provider id
- model
- temperature
- maxTokens
- reasoningEffort
- run index
- hard rule result
- judge verdict JSON
- final pass/fail
- elapsed time
- error type
- output text

人类可读摘要输出到控制台：

- 总数、通过数、失败数。
- 每个 scenario 的聚合统计：mean score、sigma（样本标准差）、score range、pass rate。
- 每个 scenario 的逐维度统计（含 dimensions 时）。
- 每个失败 case 的 id、prompt id、失败原因、score。
- JSONL 报告路径。
- 指定 `--compare` 时：回归对比报告（score 变化、pass rate 变化、回归/改进标记）。

运行结果不提交 git。需要在 `.gitignore` 忽略：

```gitignore
tool/evaluation/results/
```

## 退出码

```text
0  所有匹配 scenario 通过
1  至少一个 scenario 跑完但失败
2  配置或输入错误
3  运行时错误
```

示例：

- 数据库不存在：`2`
- 默认模型缺失：`2`
- scenario JSON 无效：`2`
- prompt id 不存在：`2`
- provider 请求失败：`3`
- Judge JSON 解析失败：`3`

## 执行顺序

多个 scenario 第一版串行执行。

原因：

- 日志和报告更容易追踪。
- 降低 provider rate limit 风险。
- 简化失败定位和中断重跑。

后续可以加 `--concurrency`，但默认仍应是 `1`。

## Prompt 优化闭环

第一版不自动优化 prompt。

推荐流程：

1. 运行 Prompt Regression Evaluation。
2. 查看硬规则失败和 Judge Agent verdict。
3. 人手动修改 `assets/prompts/**`。
4. 重新运行同一组 scenario。
5. 比较本地 JSONL 报告。

`suggestions` 字段只用于给人提供修改线索，不允许 runner 自动写 prompt。

## 后续扩展

### Full Agent Workflow Evaluation

后续完整评估应覆盖：

- read/write tools。
- fixture 数据库或项目状态。
- expected tool calls。
- forbidden tool calls。
- blocked actions。
- persisted artifacts。
- generated content quality。

评估对象会从 `prompt_id` 扩展到 `agent_slug` 或完整 agent 配置。

### 多次运行（已实现）

所有 scenario 默认 `runs: 3`。聚合规则：

- 每次 run 独立判定硬规则 + Judge Agent。
- 每次 run 独立记录 pass/fail、score、elapsed time。
- 报告输出中聚合 per-scenario 统计：mean score、sample stddev、min/max、pass rate。
- 逐维度统计（含 `dimensions` 时）：每个维度的 mean score 和 stddev。

### 多维打分（已实现）

scenario 可声明 `dimensions` 数组，Judge Agent 逐维打分：

```json
{
  "dimensions": [
    {"name": "问题识别", "weight": 0.35, "rubric": "是否准确识别了具体文本问题"},
    {"name": "连续性分析", "weight": 0.35, "rubric": "是否深入分析了连续性断裂"},
    {"name": "具体性", "weight": 0.3, "rubric": "反馈是否具体可操作"}
  ]
}
```

- 权重和必须为 1.0。
- 不指定则默认单一「综合」维度。
- Judge verdict 中 `dimensions` 数组包含逐维 score（1-5）和 comment。

### 回归对比（已实现）

通过 `--compare` 指定基线报告路径，运行评测后自动输出对比结果：

- 检测回归：mean score 下降 >0.5 或 pass rate 下降 >20pp。
- 检测改进：mean score 上升 >0.5 或 pass rate 上升 >20pp。
- 新增 scenario 不计为回归。

### Judge Model（已实现）

已支持通过 `--judge-model` CLI 参数指定独立 Judge 模型：

```bash
EVAL_ARGS="--yes --judge-model openai::gpt-4o" flutter test ...
```

- 格式：`provider_id::model`。
- Judge 模型的 provider 配置从同一数据库加载。
- 不指定时 Judge 与被测 Agent 使用同一模型。

### 增强 Judge Prompt（已实现）

Judge Agent 的系统提示已扩展，包含：评估原则（rubric 为准、区分事实与推测、关注缺失甚于冗余、检查一致性、避免光环效应）、评分参考（1-5 分描述）、常见反模式列表。

### Reference Answer

第一版不做 golden baseline。后续如需要更强对照，可以引入 `reference_answer` 作为 Judge Agent 的参考，不做逐字 diff。
