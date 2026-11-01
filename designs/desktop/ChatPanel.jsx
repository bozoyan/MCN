// AI chat panel — docked to the right of the manuscript editor.
// Mirrors lib/desktop/widgets/ai/chat/panel.dart.

// ---- Tool-activity timeline (desktop) -------------------------------
// A run of thinking + tool calls collapses into one stepped group instead
// of a wall of per-call cards. thinking 与 Read/Edit 等同属一个活动组，仅当
// LLM 返回 text 时才切到下一个 card。连续多个 LLM 响应（中间无 text 等特殊
// block）也合并进同一个活动卡——一个活动组可跨多轮，故会出现多个 thinking
// 检查点。Light detail (read preview / hit list) expands inline; diffs open
// a centered dialog (ToolDiffDialog).
function ToolDot({ status }) {
  if (status === "running") {
    return (
      <span className="m-tool__dot m-tool__dot--running">
        <span className="m-task__spinner" />
      </span>
    );
  }
  const isErr = status === "error";
  return (
    <span className={"m-tool__dot" + (isErr ? " m-tool__dot--error" : "")}>
      <Icon name={isErr ? "x" : "check"} size={11} />
    </span>
  );
}

function ToolDetailBlock({ detail }) {
  if (detail.type === "paths") {
    return (
      <div className="m-tool__block">
        <div className="m-tool__block-label">{detail.label}</div>
        <div className="m-tool__paths">
          {detail.items.map((p, i) => (
            <div className="m-tool__path" key={i}>
              <Icon name="file-text" size={12} color="var(--text-subtle)" />
              <span>{p}</span>
            </div>
          ))}
        </div>
      </div>
    );
  }
  return (
    <div className="m-tool__block">
      <div className="m-tool__block-label">{detail.label}</div>
      <div
        className="m-tool__block-text"
        style={detail.mono ? { fontFamily: "var(--font-mono)" } : null}
      >
        {detail.text}
      </div>
    </div>
  );
}

function ToolActivity({ steps, onOpenDiff }) {
  const [open, setOpen] = React.useState(true);
  const [openStep, setOpenStep] = React.useState(null);
  const running = steps.some((s) => s.status === "running");
  const stepLabel = (s) =>
    s.kind === "thinking" ? (s.status === "running" ? "思考中" : "推理过程") : s.verb;
  return (
    <div className="m-toolact">
      <button type="button" className="m-tool__head" onClick={() => setOpen((o) => !o)}>
        <Icon name="magic-wand" size={14} color="var(--accent)" />
        <span className="m-tool__head-title">执行过程</span>
        <span className={"m-tool__count" + (running ? " m-tool__count--running" : "")}>
          {running ? "运行中" : steps.length + " 步"}
        </span>
        <Icon name="caret-down" size={14} className={"m-tool__caret" + (open ? " is-open" : "")} />
      </button>
      {open ? (
        <div className="m-tool__list">
          {steps.length > 1 && <div className="m-tool__rail" />}
          {steps.map((st, i) => {
            const d = st.detail;
            const isThinking = st.kind === "thinking";
            const isDiff = d && d.type === "diff";
            const inlineable = d && d.type !== "diff";
            const clickable = !!d;
            const expanded = openStep === i;
            return (
              <React.Fragment key={i}>
                <div
                  className={"m-tool__step" + (clickable ? " is-clickable" : "")}
                  onClick={
                    !clickable
                      ? undefined
                      : isDiff
                      ? () => onOpenDiff(st)
                      : () => setOpenStep((p) => (p === i ? null : i))
                  }
                >
                  <ToolDot status={st.status} />
                  {isThinking && <Icon name="brain" size={13} color="var(--text-muted)" />}
                  <span className="m-tool__verb">{stepLabel(st)}</span>
                  {!isThinking && (
                    <span className={"m-tool__target" + (st.mono ? " m-tool__target--mono" : "")}>
                      {st.target}
                    </span>
                  )}
                  {!isThinking && !st.target && <span className="m-tool__target" />}
                  {isDiff && <Icon name="arrows-out" size={13} className="m-tool__open" />}
                  {inlineable && (
                    <Icon
                      name="caret-right"
                      size={13}
                      className={"m-tool__chev" + (expanded ? " is-open" : "")}
                    />
                  )}
                </div>
                {inlineable && expanded && (
                  <div className="m-tool__detail">
                    <ToolDetailBlock detail={d} />
                  </div>
                )}
              </React.Fragment>
            );
          })}
        </div>
      ) : (
        <div className="m-tool__summary">{steps.map(stepLabel).join(" · ")}</div>
      )}
    </div>
  );
}

// 折叠任务清单（对齐 TodoToolCard）— 一个 doing / 其余 todo / closed。
function TodoCard({ items }) {
  const [open, setOpen] = React.useState(true);
  const done = items.filter((t) => t.status === "closed").length;
  const dot = (s) =>
    s === "doing"
      ? "m-todo__dot--doing"
      : s === "closed"
      ? "m-todo__dot--closed"
      : "m-todo__dot--todo";
  return (
    <div className="m-todo">
      <button type="button" className="m-tool__head" onClick={() => setOpen((o) => !o)}>
        <Icon name="list-checks" size={14} color="var(--text-muted)" />
        <span className="m-tool__head-title">任务清单</span>
        <span className="m-tool__count">{done}/{items.length}</span>
        <Icon name="caret-down" size={14} className={"m-tool__caret" + (open ? " is-open" : "")} />
      </button>
      {open && (
        <div className="m-todo__list">
          {items.map((t, i) => (
            <div className="m-todo__row" key={i}>
              <span className={"m-todo__dot " + dot(t.status)}>
                {t.status === "closed" && <Icon name="check" size={10} />}
                {t.status === "doing" && <span className="m-task__spinner" />}
              </span>
              <span className={"m-todo__text" + (t.status === "closed" ? " is-done" : "")}>
                {t.text}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// AskUser 交互卡（对齐 AskUserCard）— 问题 + 选项 + 补充输入 + 取消/确认。
function AskUserCard({ question, options, hint }) {
  const [picked, setPicked] = React.useState(null);
  const [extra, setExtra] = React.useState("");
  return (
    <div className="m-ask">
      <div className="m-ask__head">
        <Icon name="question" size={14} color="var(--accent-warm)" />
        <span className="m-ask__title">需要你确认</span>
      </div>
      <div className="m-ask__question">{question}</div>
      <div className="m-ask__options">
        {options.map((o, i) => (
          <button
            type="button"
            key={i}
            className={"m-ask__option" + (picked === i ? " is-picked" : "")}
            onClick={() => setPicked(i)}
          >
            <span className={"m-ask__radio" + (picked === i ? " is-on" : "")} />
            <span>{o.label}</span>
          </button>
        ))}
      </div>
      {hint && (
        <input
          className="m-ask__input"
          placeholder={hint}
          value={extra}
          onChange={(e) => setExtra(e.target.value)}
        />
      )}
      <div className="m-ask__actions">
        <button type="button" className="m-btn m-btn--ghost m-btn--sm">取消</button>
        <button type="button" className="m-btn m-btn--primary m-btn--sm" disabled={picked === null}>
          确认
        </button>
      </div>
    </div>
  );
}

function ToolDiffDialog({ step, onClose }) {
  const d = step.detail;
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog m-dialog--diff" onClick={(e) => e.stopPropagation()}>
        <div className="m-dialog__head">
          <div className="m-chat__head-l">
            <Icon name={step.icon || "note-pencil"} size={16} />
            <span className="m-ui-semibold">{step.verb}</span>
            <span className="m-tool__target" style={{ flex: "none", color: "var(--text-muted)" }}>
              {step.target}
            </span>
          </div>
          <button className="m-icon-btn" title="关闭" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        </div>
        <div className="m-diff">
          <div className="m-diff__block m-diff__block--old">
            <div className="m-diff__label">原文</div>
            <div className="m-diff__text m-diff__text--old">{d.old}</div>
          </div>
          <div className="m-diff__block m-diff__block--new">
            <div className="m-diff__label">改为</div>
            <div className="m-diff__text">{d.now}</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ChatBubble({ role, content, blocks, reference, streaming, onOpenDiff }) {
  if (role === "user") {
    return (
      <div className="m-bubble m-bubble--user">
        {/* 用户消息操作（对齐图1）：回退固定常驻，复制/删除 hover 显示。
           所有按钮在气泡左侧。回退 = 回滚本轮对作品的改动 + 移除本轮 AI 回复
           + 把 prompt 放回输入框（见 chat-changes-rework.md PR-6/PR-8）。*/}
        <div className="m-bubble__uactions">
          <button className="m-icon-btn m-icon-btn--ghost m-bubble__uaction--hover" title="复制">
            <Icon name="copy" size={12} />
          </button>
          <button className="m-icon-btn m-icon-btn--ghost m-bubble__uaction--hover" title="删除">
            <Icon name="trash-simple" size={12} />
          </button>
          <button
            className="m-icon-btn m-icon-btn--ghost"
            title="回退到本轮对话发起前"
          >
            <Icon name="arrow-counter-clockwise" size={13} />
          </button>
        </div>
        <div className="m-bubble__content">{content}</div>
      </div>
    );
  }
  return (
    <div className="m-bubble m-bubble--ai">
      <div className="m-bubble__avatar">
        <Icon name="sparkle" size={12} />
      </div>
      <div className="m-bubble__col">
        <div className="m-ui-tiny" style={{ marginBottom: 4 }}>主笔 · Primary agent</div>
        {(blocks || []).map((b, i) => {
          if (b.type === "activity") {
            return <ToolActivity key={i} steps={b.steps} onOpenDiff={onOpenDiff} />;
          }
          if (b.type === "todo") {
            return <TodoCard key={i} items={b.items} />;
          }
          if (b.type === "askUser") {
            return (
              <AskUserCard
                key={i}
                question={b.question}
                options={b.options}
                hint={b.hint}
              />
            );
          }
          if (b.type === "text") {
            // 复制按钮随每段文本 hover 显示、左对齐（对齐 CollapsibleTextBlock）。
            return (
              <div className="m-bubble__text" key={i}>
                <div className="m-bubble__content">{b.text}</div>
                <button className="m-icon-btn m-icon-btn--ghost m-bubble__copy" title="复制">
                  <Icon name="copy" size={12} />
                </button>
              </div>
            );
          }
          return null;
        })}
        {reference && (
          <div className="m-bubble__ref">
            <Icon name="file-text" size={12} />
            <span>{reference}</span>
          </div>
        )}
        {!streaming && (
          <div className="m-bubble__actions">
            {/* blocks 消息底部仅 反馈 / 分叉；复制随每段文本 hover 显示 —
               对齐 chat_message_view.dart 的 MessageActionBar(onFeedback, onFork) */}
            <button className="m-icon-btn m-icon-btn--ghost" title="反馈">
              <Icon name="bug-beetle" size={12} />
            </button>
            <button className="m-icon-btn m-icon-btn--ghost" title="分叉会话">
              <Icon name="git-fork" size={12} />
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// 顶部任务面板（对齐 lib/shared/widgets/ai/chat/todo_panel.dart 的 TodoPanel）—
// 固定在会话上下文条与消息列表之间，可折叠；行含状态图标 + 优先级点 + 内容。
const CHAT_TODOS = [
  { text: "拆分第三章首段，让伏笔分三拍呈现", status: "completed", priority: "medium" },
  { text: "把老沈的木匣线索后置到第六段", status: "completed", priority: "high" },
  { text: "校对三人对白语气", status: "in_progress", priority: "high" },
  { text: "确认木匣伏笔的回收时机", status: "pending", priority: "medium" },
  { text: "统一卷一雨势描写用词", status: "cancelled", priority: "low" },
];
const TODO_ROW = {
  pending:     { icon: "circle",       color: "var(--text-muted)",      text: "var(--text-secondary)", strike: false },
  in_progress: { icon: "circle",       color: "var(--accent)",          text: "var(--text-primary)",   strike: false },
  completed:   { icon: "check-circle", color: "var(--addition-border)", text: "var(--text-muted)",     strike: true  },
  cancelled:   { icon: "x-circle",     color: "var(--deletion-border)", text: "var(--text-muted)",     strike: true  },
};
const TODO_PRIO = { high: "var(--deletion-border)", medium: "var(--accent-warm)", low: "var(--text-muted)" };

function TopTodoPanel({ todos }) {
  const [open, setOpen] = React.useState(false);
  const total = todos.length;
  const done = todos.filter((t) => t.status === "completed").length;
  const pending = todos.filter(
    (t) => t.status !== "completed" && t.status !== "cancelled"
  ).length;
  const inProgress = todos.some((t) => t.status === "in_progress");
  const allDone = pending === 0;
  return (
    <div className="m-todobar">
      <button
        type="button"
        className={"m-tool__head" + (open ? " is-open" : "")}
        onClick={() => setOpen((o) => !o)}
      >
        <Icon
          name={allDone ? "check-circle" : "list-checks"}
          size={15}
          color={
            inProgress
              ? "var(--accent)"
              : allDone
              ? "var(--addition-border)"
              : "var(--text-muted)"
          }
        />
        <span className="m-tool__head-title" style={{ color: "var(--text-primary)" }}>
          任务列表
        </span>
        <span
          className="m-todobar__badge"
          style={{
            color: allDone ? "var(--addition-border)" : "var(--accent)",
            background: allDone ? "color-mix(in srgb, var(--success) 12%, transparent)" : "color-mix(in srgb, var(--accent) 14%, transparent)",
          }}
        >
          {done}/{total}
        </span>
        <Icon name="caret-down" size={14} className={"m-tool__caret" + (open ? " is-open" : "")} />
      </button>
      {open && (
        <div className="m-todobar__list">
          {todos.map((t, i) => {
            const r = TODO_ROW[t.status] || TODO_ROW.pending;
            return (
              <div className="m-todobar__row" key={i}>
                <Icon name={r.icon} size={15} color={r.color} />
                <span className="m-todobar__prio" style={{ background: TODO_PRIO[t.priority] }} />
                <span
                  className="m-todobar__text"
                  style={{ color: r.text, textDecoration: r.strike ? "line-through" : "none" }}
                >
                  {t.text}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// 本次会话用量只在 header 留一枚 chip（提案）：让开销在花之前就可见，
// 点击进入 设置 → 用量 →「会话」tab 的该会话详情。构成、子代理下钻、上下文
// 窗口都归那一页承载，聊天面板不再背这块内容。
// 最近变更日志（替代原"待确认卡"）— 默认接受后 AI 改动已自动应用，此卡不再是
// "接受吗"的决策门，而是"本会话最近改了哪些" + 逐条/全部回退。
// 去掉行数 +X -Y（散文里 line≠意义单位），改用改动类型标签（新增/改写/扩写/删减）。
// 精确 diff 仍由「查看变更」的 detail dialog 承载。
// 对齐方案 docs/solutions/chat-changes-rework.md（决策一/二 + PR-7）。
const CHANGE_TYPE = {
  create:  { label: "新增", color: "var(--accent-warm)" },
  rewrite: { label: "改写", color: "var(--accent)" },
  expand:  { label: "扩写", color: "var(--addition-border)" },
  trim:    { label: "删减", color: "var(--deletion-border)" },
};
const RECENT_CHANGES = [
  { title: "第 03 章 · 三舱客", sub: "正文", change: "rewrite" },
  { title: "凤瑶", sub: "简介", change: "create" },
];

function ChangeTypeTag({ change }) {
  const t = CHANGE_TYPE[change] || CHANGE_TYPE.rewrite;
  return (
    <span className="m-ctag" style={{ color: t.color }}>
      {t.label}
    </span>
  );
}

// onRevert / onRevertAll 可选:制片页(drama/chat.jsx)接上真实回退,写作页仍是静态演示。
function RecentChangesLog({ changes, onClose, onRevert, onRevertAll }) {
  const [open, setOpen] = React.useState(true);
  return (
    <div className="m-pchg">
      <div className={"m-pchg__head" + (open ? " is-open" : "")}>
        <Icon name="clock-counter-clockwise" size={15} color="var(--text-muted)" />
        <span className="m-pchg__title">最近改动 · {changes.length} 处</span>
        <span className="m-pchg__spacer" />
        <button type="button" className="m-pchg__view">查看变更</button>
        <button
          type="button"
          className="m-icon-btn"
          title={open ? "收起" : "展开"}
          onClick={() => setOpen((o) => !o)}
        >
          <Icon name={open ? "caret-up" : "caret-down"} size={14} />
        </button>
        {onClose && (
          <button type="button" className="m-icon-btn" title="关闭" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        )}
      </div>
      {open && (
        <div className="m-pchg__body">
          <div className="m-pchg__hint">
            AI 改动已自动应用，如需撤销可逐条或全部回退。
          </div>
          {changes.map((c, i) => {
            const create = c.change === "create";
            return (
              <div className="m-pchg__row" key={i}>
                <Icon
                  name={create ? "plus" : "note-pencil"}
                  size={18}
                  color={create ? "var(--accent-warm)" : "var(--text-muted)"}
                />
                <div className="m-pchg__row-main">
                  <span className="m-pchg__row-title">{c.title}</span>
                  {c.sub && <span className="m-pchg__row-sub">{c.sub}</span>}
                </div>
                <ChangeTypeTag change={c.change} />
                <button type="button" className="m-icon-btn m-icon-btn--ghost" title="回退此项" onClick={() => onRevert && onRevert(c)}>
                  <Icon name="arrow-counter-clockwise" size={14} color="var(--text-muted)" />
                </button>
              </div>
            );
          })}
          <div className="m-pchg__actions">
            <button type="button" className="m-btn m-btn--ghost m-btn--sm" onClick={onRevertAll}>
              全部回退
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── 下一步建议 ─────────────────────────────────────────────────────────────
   来源是模型的 SuggestNextAction 工具调用，不是客户端规则。所以：
   1. 模型没挂建议 → 整条不渲染，不占高度（下面第一行的 early return）；
   2. 文案是模型运行时给的，不走 i18n，因此这里的 label 写成贴合当前章节的样子，
      而不是「继续写下一章」这种模板话；
   3. kind=prompt 点了填进输入框（不自动发送）；kind=feature 点了跳去对应功能，
      seed 作为目标页议题 / 场景的预填。 */
const NEXT_ACTION_ICON = {
  prompt: "lightbulb",
  ai_council: "users-three",
  ai_theater: "mask-happy",
  ai_cover_studio: "image",
};

// 模型在「刚聊完木匣该不该交代」这一轮收尾挂的三条建议。
const NEXT_ACTIONS_SAMPLE = [
  { kind: "prompt", label: "核对第 03 章的时间线与老沈行踪" },
  { kind: "feature", feature: "ai_council", label: "木匣的交代时机去圆桌听几个视角" },
  { kind: "feature", feature: "ai_theater", label: "先把三舱对峙演一遍" },
];

// ---- 后台子任务条（composer 上方）---------------------------------
// 对齐 lib/shared/widgets/ai/chat/background_agents.dart。
//
// 一个任务一行尽显，不出汇总行 —— 只有一项时没有可折叠的内容。两个以上收成
// 「N 个后台任务 · 名字」汇总行 + 折叠箭头，展开后才出现「全部停止」。
// task 原文不上条：详情弹窗里有完整版，条上永远只是截断的半句话。
// 「重启后未在运行」不属于这里 —— 条上只列当前 runtime 里活着的后台 run，
// 那个状态由消息流里的活动卡表达（aiBackgroundNotRunning）。
const BG_RUNS_SAMPLE = [
  { id: "r1", name: "猫腻", agent: "内容核验", emoji: "🔍", activity: "查看 大纲 · 全书总纲", elapsed: 134 },
  { id: "r2", name: "江南", agent: "情节推演", emoji: "🧭", activity: "深度思考", elapsed: 41 },
];

function fmtElapsed(total) {
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function BackgroundAgentRow({ run, onStop }) {
  const done = run.status === "done";
  const stopping = run.status === "stopping";
  return (
    <div className="m-bga__row">
      <span
        className={"m-bga__avatar" + (done ? " m-bga__avatar--done" : " m-bga__avatar--run")}
        title={run.agent}
      >
        {done ? <Icon name="check" size={11} /> : run.emoji}
      </span>
      <span className="m-bga__name" title={run.name + " · " + run.agent}>
        {run.name}
      </span>
      <span
        className={
          "m-bga__act" +
          (done ? " m-bga__act--done" : stopping ? " m-bga__act--stopping" : "")
        }
      >
        {done ? "已完成 · 查看结果" : stopping ? "停止中…" : run.activity}
      </span>
      {!done && <span className="m-bga__time">{fmtElapsed(run.elapsed)}</span>}
      <button type="button" className="m-bga__btn" title={"查看 " + run.name + " 的完整会话"}>
        <Icon name="arrows-out" size={13} />
      </button>
      {/* 停止而非暂停 —— cancelRun 不可恢复，图标和文案都不该说「暂停」。 */}
      {done ? (
        <span className="m-bga__slot" />
      ) : (
        <button
          type="button"
          className="m-bga__btn m-bga__btn--stop"
          title={stopping ? "停止中" : "停止 " + run.name}
          disabled={stopping}
          onClick={() => onStop(run.id)}
        >
          <span className="m-bga__stopmark" />
        </button>
      )}
    </div>
  );
}

function BackgroundAgents() {
  const [runs, setRuns] = React.useState(() =>
    BG_RUNS_SAMPLE.map((r) => ({ ...r, status: "running" }))
  );
  const [open, setOpen] = React.useState(true);
  // 原型里让时长自己走；真实实现按 run.startedAt 算差值，不存计数器。
  React.useEffect(() => {
    const timer = setInterval(
      () =>
        setRuns((rs) =>
          rs.map((r) => (r.status === "running" ? { ...r, elapsed: r.elapsed + 1 } : r))
        ),
      1000
    );
    return () => clearInterval(timer);
  }, []);

  const stop = (id) => {
    // StopAgent 的返回只确认请求已接收，最终状态以任务实际结束为准。
    setRuns((rs) => rs.map((r) => (r.id === id ? { ...r, status: "stopping" } : r)));
    setTimeout(
      () => setRuns((rs) => rs.map((r) => (r.id === id ? { ...r, status: "done" } : r))),
      1200
    );
    // 完成项留 6 秒给用户一个回执再移除，结果本身留在消息流里。
    setTimeout(() => setRuns((rs) => rs.filter((r) => r.id !== id)), 7200);
  };

  if (runs.length === 0) return null;
  const live = runs.filter((r) => r.status !== "done");
  const multi = runs.length > 1;
  return (
    <div className="m-bga">
      {multi && (
        <div
          className={"m-bga__head" + (open ? " is-open" : "")}
          onClick={() => setOpen((o) => !o)}
        >
          {/* 全部停止后到完成项移除之前，live 是 0 —— 那时候不该继续转圈报 0 个。 */}
          {live.length > 0 ? (
            <span className="m-bga__spin" />
          ) : (
            <span className="m-bga__avatar m-bga__avatar--done">
              <Icon name="check" size={11} />
            </span>
          )}
          <span className="m-bga__title">
            {live.length > 0 ? live.length + " 个后台任务" : "后台任务已结束"}
          </span>
          {open ? (
            <span className="m-bga__names" />
          ) : (
            <span className="m-bga__names">· {runs.map((r) => r.name).join("、")}</span>
          )}
          {open && live.length > 1 && (
            <button
              type="button"
              className="m-bga__stopall"
              onClick={(e) => {
                e.stopPropagation();
                live.forEach((r) => stop(r.id));
              }}
            >
              全部停止
            </button>
          )}
          <Icon
            name="caret-down"
            size={14}
            className={"m-bga__caret" + (open ? " is-open" : "")}
          />
        </div>
      )}
      {(!multi || open) && (
        <div className="m-bga__list">
          {runs.map((r) => (
            <BackgroundAgentRow key={r.id} run={r} onStop={stop} />
          ))}
        </div>
      )}
    </div>
  );
}

function NextActionBar({ actions, onPick }) {
  // 没有建议就什么都不显示 —— 对齐 NextActionBar 的 SizedBox.shrink()。
  if (!actions || actions.length === 0) return null;
  return (
    <div className="m-nextact">
      <div className="m-nextact__head">
        <Icon name="lightbulb" size={11} color="var(--text-subtle)" />
        <span className="m-nextact__title">下一步</span>
      </div>
      <div className="m-nextact__row">
        {actions.map((a, i) => {
          const goto = a.kind === "feature";
          return (
            <button
              type="button"
              key={i}
              className={"m-nextact__chip" + (goto ? " m-nextact__chip--goto" : "")}
              onClick={() => onPick && onPick(a)}
              title={goto ? "离开当前对话，跳到对应功能" : "填入输入框，可改后再发送"}
            >
              <Icon
                name={NEXT_ACTION_ICON[goto ? a.feature : "prompt"]}
                size={13}
                color={goto ? "var(--accent)" : "var(--text-muted)"}
              />
              <span className="m-nextact__label">{a.label}</span>
              {goto && <Icon name="arrow-right" size={11} color="var(--text-subtle)" />}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ── 空会话欢迎态 ───────────────────────────────────────────────────────────
   空会话时一次模型调用都还没发生，所以这四条来自客户端固定目录，不是模型给的。
   封面那条只在「没封面 + 书名简介已确认 + 已配图像模型」时才出现。 */
const EMPTY_STATE_ACTIONS = [
  {
    kind: "prompt",
    icon: "list-checks",
    title: "规划今天的工作",
    sub: "围绕接下来三章安排今日写作。",
  },
  {
    kind: "feature",
    feature: "ai_council",
    icon: "users-three",
    title: "和多位专家讨论剧情",
    sub: "换几个视角看看这段该往哪走。",
  },
  {
    kind: "feature",
    feature: "ai_theater",
    icon: "mask-happy",
    title: "不知道怎么写？先演一遍",
    sub: "让角色把这场戏演出来，再决定怎么落笔。",
  },
  {
    kind: "feature",
    feature: "ai_cover_studio",
    icon: "image",
    title: "给作品做一张封面",
    sub: "书名和简介都齐了，配张封面上书架。",
  },
];

function AssistantEmptyState({ actions, onPick }) {
  return (
    <div className="m-cempty">
      <div className="m-cempty__art">
        <span className="m-cempty__mark">
          <Icon name="book-open" size={36} color="var(--accent)" />
        </span>
      </div>
      <div className="m-cempty__welcome">{"慢慢写，我会陪你一起\n整理灵感与情节。"}</div>
      <div className="m-cempty__label">你可以这样开始</div>
      <div className="m-cempty__list">
        {actions.map((a, i) => (
          <button type="button" key={i} className="m-cempty__tile" onClick={() => onPick && onPick(a)}>
            <span className="m-cempty__badge">
              <Icon name={a.icon} size={17} color="var(--accent)" />
            </span>
            <span className="m-cempty__body">
              <span className="m-cempty__t">{a.title}</span>
              <span className="m-cempty__s">{a.sub}</span>
            </span>
            <Icon name="arrow-right" size={14} color="var(--text-subtle)" />
          </button>
        ))}
      </div>
    </div>
  );
}

/* mockup 专用：三态对照。真实产品里没有这个控件。 */
const DEMO_STATES = [
  { id: "suggest", label: "有建议" },
  { id: "none", label: "无建议" },
  { id: "empty", label: "空会话" },
];

function ChatPanel({ onClose, onSwitchPane, onOpenUsage }) {
  const D = window.REVERIC_DATA;
  const usage = window.SESSION_USAGE[window.CURRENT_SESSION_ID];
  const [text, setText] = React.useState("");
  const [diffStep, setDiffStep] = React.useState(null);
  const [demo, setDemo] = React.useState("suggest");

  const isEmpty = demo === "empty";
  const nextActions = demo === "suggest" ? NEXT_ACTIONS_SAMPLE : [];

  // 点建议：prompt 类填进输入框（不自动发送）；feature 类在真实产品里会跳走。
  const pickAction = (a) => {
    if (a.kind === "prompt") setText(a.label);
  };

  return (
    <aside className="m-chat">
      <div className="m-chat__head">
        <div className="m-chat__head-l">
          <Icon name="chat-circle-text" size={16} />
          <span className="m-ui-semibold">写作助手</span>
        </div>
        <div className="m-chat__head-r">
          {/* 常驻用量 chip（提案）— 点击进入 设置 → 用量 →「会话」本会话详情 */}
          <span
            className="m-usechip"
            title="本次会话用量"
            onClick={() => onOpenUsage && onOpenUsage(usage.id)}
          >
            <b>{usage.total}</b> · 上下文 <b>{usage.context.pct}%</b>
          </span>
          {/* 对齐真实 header.dart 的 _HeaderActions：展开 / 新会话 / 关闭 */}
          <button className="m-icon-btn" title="展开">
            <Icon name="arrows-out" size={14} />
          </button>
          <button className="m-icon-btn" title="新会话">
            <Icon name="note-pencil" size={14} />
          </button>
          <button className="m-icon-btn" title="关闭" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>

      {/* mockup 专用：切换「有建议 / 无建议 / 空会话」三态对照 */}
      <div className="m-demoswitch">
        <span className="m-demoswitch__tag">演示态</span>
        {DEMO_STATES.map((s) => (
          <button
            type="button"
            key={s.id}
            className={"m-demoswitch__btn" + (demo === s.id ? " is-on" : "")}
            onClick={() => setDemo(s.id)}
          >
            {s.label}
          </button>
        ))}
      </div>

      <div className="m-chat__context">
        <Icon name="article" size={12} />
        <span>当前上下文：第 03 章 · 三舱客 · 周清远视角</span>
      </div>

      {!isEmpty && <TopTodoPanel todos={CHAT_TODOS} />}

      <div className="m-chat__scroll">
        {isEmpty ? (
          <AssistantEmptyState actions={EMPTY_STATE_ACTIONS} onPick={pickAction} />
        ) : (
          D.chatMessages.map((m, i) => <ChatBubble key={i} {...m} onOpenDiff={setDiffStep} />)
        )}
      </div>

      {diffStep && <ToolDiffDialog step={diffStep} onClose={() => setDiffStep(null)} />}

      {!isEmpty && (
        <div style={{ margin: "0 var(--space-lg)" }}>
          <RecentChangesLog changes={RECENT_CHANGES} />
        </div>
      )}

      {/* 输入区正上方。无建议时 NextActionBar 自己返回 null，这里不留占位。 */}
      <NextActionBar actions={nextActions} onPick={pickAction} />

      {/* composer 正上方。没有后台任务时自己返回 null。 */}
      <BackgroundAgents />

      <div className="m-composer">
        {/* 输入区顶部引用 chip（对齐 composer.dart 的 _ReferenceChip / 附加引用）*/}
        <div className="m-composer__refs">
          <span className="m-cref">
            <Icon name="users" size={12} color="var(--accent)" />
            <span>周清远</span>
            <Icon name="x" size={10} color="var(--accent)" />
          </span>
          <span className="m-cref">
            <Icon name="users" size={12} color="var(--accent)" />
            <span>凤瑶</span>
            <Icon name="x" size={10} color="var(--accent)" />
          </span>
        </div>
        <div className="m-composer__field">
          <textarea
            className="m-composer__input"
            rows={3}
            placeholder="对当前章节提问，或描述想要的修改…"
            value={text}
            onChange={(e) => setText(e.target.value)}
            spellCheck={false}
          />
        </div>
        {/* 底部工具栏对齐 composer.dart：仅右侧模型选择 + 圆形上箭头发送，无左侧工具图标 */}
        <div className="m-composer__toolbar">
          <div style={{ flex: 1 }} />
          <ComposerModelSelect initial="mimo-v2.5 · 默认" />
          <button className="m-composer__send" title="发送">
            <Icon name="arrow-up" size={18} />
          </button>
        </div>
      </div>
    </aside>
  );
}

Object.assign(window, { ChatPanel });
