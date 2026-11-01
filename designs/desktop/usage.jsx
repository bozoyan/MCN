// Usage statistics settings page.
// Base层 mirrors lib/shared/widgets/settings/usage_view.dart: token consumption
// stat cards (with breakdown + trend), 30-day stacked bar chart, and the
// paginated usage records table.
//
// 提案层（尚未在 Flutter 侧实现，用于回答「词元花在哪」）：
//   · 页面分「总览 / 会话」两个 tab，使用分段导航
//   · 总览：来源筛选 + 「按功能分布」+ 30 天图表可按功能着色
//   · 会话：会话列表 → 下钻单个会话的构成（主线 / 子代理，子代理再到每次运行）
// 分类只按用户发起的功能切；自动压缩的开销并入触发它的一方，界面上不出现。
// 写入侧缺口：子代理的用量目前记在父会话与父模型上、子代理的上下文压缩完全
// 未记账、roleplay/monologue/theater/council 未装 UsageHook。
// 口径全部为词元。

// Breakdown / chart colors (match the Flutter widget exactly).
const BD = {
  input: "var(--accent)",
  cacheRead: "var(--addition-border)",
  cacheWrite: "var(--accent-warm)",
  output: "var(--text-muted)",
  reasoning: "var(--warning-text)",
};

// 配色：总览按功能（聊天 / 角色扮演 / …），会话构成按主线 / 子代理。
const SRC_COLOR = {
  chat: "var(--accent)",
  roleplay: "var(--warning-text)",
  monologue: "var(--text-subtle)",
  theater: "var(--text-subtle)",
  council: "var(--text-subtle)",
  other: "var(--text-subtle)",
  // 仅用于会话构成树。
  subagent: "var(--accent-amber)",
};

const USAGE_TYPES = [
  { k: "input", label: "输入", color: BD.input },
  { k: "cacheRead", label: "缓存读取", color: BD.cacheRead },
  { k: "cacheWrite", label: "缓存写入", color: BD.cacheWrite },
  { k: "output", label: "输出", color: BD.output },
];

const fmtK = (k) => (k >= 1000 ? (k / 1000).toFixed(2) + "M" : k + "K");

function UsageSection({ initialTab, initialSessionId }) {
  const [tab, setTab] = React.useState(initialTab || "overview");

  return (
    <div className="sp-usage">
      <div className="sp-usage__title">用量</div>
      <p className="sp-usage__desc">所有 AI 提供商的词元消耗统计。</p>
      <div style={{ height: "var(--space-3xl)" }} />

      <div className="m-segmented" style={{ display: "flex", width: "100%" }}>
        {[
          { k: "overview", icon: "chart-bar", label: "总览" },
          { k: "sessions", icon: "chats-circle", label: "会话" },
        ].map((t) => (
          <button
            key={t.k}
            type="button"
            className={"m-segmented__item" + (tab === t.k ? " is-active" : "")}
            onClick={() => setTab(t.k)}
            style={{ flex: 1, justifyContent: "center" }}
          >
            <Icon name={t.icon} size={14} />{t.label}
          </button>
        ))}
      </div>
      <div style={{ height: "var(--space-4xl)" }} />

      {tab === "overview" ? (
        <UsageOverviewTab />
      ) : (
        <UsageSessionsTab initialSessionId={initialSessionId} />
      )}
    </div>
  );
}

// ── 总览 ────────────────────────────────────────────────────────────────────
function UsageOverviewTab() {
  const [source, setSource] = React.useState("");   // "" = 全部来源

  return (
    <React.Fragment>
      <ActivityHeatmap />
      <div style={{ height: "var(--space-4xl)" }} />

      <div className="sp-sec-header">词元消耗</div>
      <div style={{ height: "var(--space-md)" }} />
      <div className="sp-filters">
        <div className="sp-filter sp-filter--provider">
          <span className="sp-filter__label">提供商</span>
          <div className="sp-select"><span>全部提供商</span><Icon name="caret-down" size={13} /></div>
        </div>
        <div className="sp-filter sp-filter--model">
          <span className="sp-filter__label">模型</span>
          <div className="sp-select"><span>全部模型</span><Icon name="caret-down" size={13} /></div>
        </div>
        <div className="sp-filter sp-filter--source">
          <span className="sp-filter__label">来源</span>
          <SourceSelect value={source} onChange={setSource} />
        </div>
      </div>
      <div style={{ height: "var(--space-lg)" }} />
      <TokenCards />
      <div style={{ height: "var(--space-4xl)" }} />

      <div className="sp-sec-row">
        <span className="sp-sec-header">按功能分布</span>
        <span className="sp-page-of" style={{ marginLeft: "auto" }}>本月 · {USAGE.month.total} 词元</span>
      </div>
      <div style={{ height: "var(--space-md)" }} />
      <SourceDistribution highlight={source} />
      <div style={{ height: "var(--space-4xl)" }} />

      <DailyChart />
      <div style={{ height: "var(--space-4xl)" }} />

      <div className="sp-sec-header">用量明细</div>
      <div style={{ height: "var(--space-lg)" }} />
      <RecordsTable records={USAGE.records} page={USAGE.page} />
    </React.Fragment>
  );
}

// 活动热力图 — 复刻 usage_view.dart 的 _UsageHeatmap / _ActivityGrid：
// 7 行（周日→周六）× 26 周，格子 12px，4 档 accent 混色，hover 出当天词元与请求数。
function ActivityHeatmap() {
  const max = USAGE_ACTIVITY.reduce((m, c) => (c.tokens > m ? c.tokens : m), 0);
  const cellColor = (c) => {
    if (c.future || !c.tokens || !max) return "var(--surface-container)";
    const level = Math.ceil((c.tokens / max) * 4);
    const pct = { 1: 25, 2: 50, 3: 75 }[level] || 100;
    return `color-mix(in srgb, var(--accent) ${pct}%, var(--surface-container))`;
  };
  return (
    <div className="sp-surface-card">
      <div className="sp-chart-card__title">活动</div>
      <div className="sp-heat">
        {[0, 1, 2, 3, 4, 5, 6].map((dow) => (
          <div className="sp-heat__row" key={dow}>
            {Array.from({ length: ACTIVITY_WEEKS }, (_, week) => {
              const c = USAGE_ACTIVITY[week * 7 + dow];
              return (
                <span
                  key={week}
                  className="sp-heat__cell"
                  style={{ background: cellColor(c) }}
                  title={`${c.date}\n${fmtTokens(c.tokens)} 词元\n${c.requests} API 调用`}
                />
              );
            })}
          </div>
        ))}
      </div>
    </div>
  );
}

// 将词元数量格式化为 K / M。
function fmtTokens(n) {
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
  if (n >= 1000) return (n / 1000).toFixed(0) + "K";
  return String(n);
}

// 来源筛选 — 与「按功能分布」联动高亮，不做真实过滤（mockup）。
function SourceSelect({ value, onChange }) {
  const [open, setOpen] = React.useState(false);
  const current = USAGE.sources.find((s) => s.key === value);
  return (
    <div className={"m-select-wrap" + (open ? " is-open" : "")}>
      <div className="sp-select" onClick={() => setOpen((o) => !o)}>
        <span>{current ? current.name : "全部来源"}</span>
        <Icon name="caret-down" size={13} className="m-select__caret" />
      </div>
      {open && (
        <div className="m-select__menu">
          {[{ key: "", name: "全部来源", icon: "list-bullets" }].concat(USAGE.sources).map((s) => (
            <button
              type="button"
              key={s.key || "all"}
              className={"m-select__item" + (s.key === value ? " is-selected" : "")}
              onClick={() => { onChange(s.key); setOpen(false); }}
            >
              <Icon name={s.icon} size={14} className="m-select__item-icon" />
              <span className="m-select__item-meta">
                <span className="m-select__item-name">{s.name}</span>
              </span>
              {s.key === value && <Icon name="check" size={13} className="m-select__item-check" />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function BreakdownLine({ color, label, value }) {
  return (
    <div className="sp-breakdown-line">
      <span className="sp-breakdown-dot" style={{ background: color }} />
      <span className="sp-breakdown-label">{label}</span>
      <span className="sp-breakdown-val">{value}</span>
    </div>
  );
}

function Breakdown({ b }) {
  return (
    <div>
      <BreakdownLine color={BD.input} label="输入" value={b.input} />
      <BreakdownLine color={BD.cacheRead} label="缓存读取" value={b.cacheRead} />
      <BreakdownLine color={BD.cacheWrite} label="缓存写入" value={b.cacheWrite} />
      <BreakdownLine color={BD.output} label="输出" value={b.output} />
      {b.reasoning && b.reasoning !== "0" && <BreakdownLine color={BD.reasoning} label="推理" value={b.reasoning} />}
    </div>
  );
}

function StatCard({ label, value, sub, trend, breakdown, compact }) {
  return (
    <div className="sp-surface-card" style={compact ? { padding: "var(--space-3xl)" } : null}>
      <div className="sp-stat-card__label">{label}</div>
      <div className="sp-stat-card__value">
        <span className="sp-stat-card__num">{value}</span>
        <span className="sp-stat-card__sub">{sub}</span>
      </div>
      {trend}
      {breakdown && (
        <React.Fragment>
          <div className="sp-stat-divider" />
          {breakdown}
        </React.Fragment>
      )}
    </div>
  );
}

function TokenCards() {
  const t = USAGE.today, m = USAGE.month;
  const trend = (
    <div className="sp-trend" style={{ color: m.trendUp ? "var(--warning-text)" : "var(--addition-border)" }}>
      <Icon name={m.trendUp ? "trend-up" : "trend-down"} size={12} />
      <span>较上月 {m.trend}</span>
    </div>
  );
  return (
    <div>
      <div className="sp-stat-row">
        <StatCard label="本日" value={t.total} sub="词元" breakdown={<Breakdown b={t.b} />} />
        <StatCard label="本月" value={m.total} sub="词元" trend={trend} breakdown={<Breakdown b={m.b} />} />
      </div>
      <div className="sp-stat-row" style={{ marginBottom: 0 }}>
        <StatCard label="今日请求" value={String(t.requests)} sub="API 调用" compact />
        <StatCard label="日平均值" value={m.avgPerDay} sub="词元" compact />
      </div>
    </div>
  );
}

function SourceDistribution({ highlight }) {
  const total = USAGE.sources.reduce((a, s) => a + s.k, 0);
  const max = USAGE.sources[0].k;
  return (
    <div className="sp-surface-card">
      <div className="sp-dist__stack">
        {USAGE.sources.map((s) => (
          <span
            key={s.key}
            className="sp-dist__stack-seg"
            style={{
              width: (s.k / total) * 100 + "%",
              background: SRC_COLOR[s.key],
              opacity: !highlight || highlight === s.key ? 1 : 0.25,
            }}
          />
        ))}
      </div>
      {USAGE.sources.map((s) => (
        <div
          key={s.key}
          className={"sp-dist__row" + (highlight && highlight !== s.key ? " is-dim" : "")}
        >
          <span className="sp-dist__name">
            <Icon name={s.icon} size={14} />
            {s.name}
          </span>
          <span className="sp-dist__track">
            <span className="sp-dist__fill" style={{ width: (s.k / max) * 100 + "%", background: SRC_COLOR[s.key] }} />
          </span>
          <span className="sp-dist__tok">{fmtK(s.k)}</span>
          <span className="sp-dist__pct">{((s.k / total) * 100).toFixed(1)}%</span>
        </div>
      ))}
    </div>
  );
}

// 同一组数据两种着色：按词元类型（现状）/ 按功能（提案，来自 source 维度）。
const CHART_SERIES = {
  type: USAGE_TYPES.map((t) => ({ k: t.k, label: t.label, color: t.color })),
  source: [
    { k: "chat", label: "聊天", color: SRC_COLOR.chat },
    { k: "roleplay", label: "角色扮演", color: SRC_COLOR.roleplay },
    { k: "other", label: "其他功能", color: SRC_COLOR.other },
  ],
};

function DailyChart() {
  const [mode, setMode] = React.useState("type");
  const series = CHART_SERIES[mode];
  const maxStacked = Math.max(
    ...USAGE_DAILY.map((d) => series.reduce((a, s) => a + d[s.k], 0))
  );
  const H = 180;
  return (
    <div className="sp-surface-card">
      <div className="sp-sec-row">
        <div>
          <div className="sp-chart-card__title">每日词元用量</div>
          <div className="sp-chart-card__sub">过去 30 天</div>
        </div>
        <div className="sp-seg">
          <button
            type="button"
            className={"sp-seg__btn" + (mode === "type" ? " is-on" : "")}
            onClick={() => setMode("type")}
          >
            按词元类型
          </button>
          <button
            type="button"
            className={"sp-seg__btn" + (mode === "source" ? " is-on" : "")}
            onClick={() => setMode("source")}
          >
            按功能
          </button>
        </div>
      </div>
      <div className="sp-legend">
        {series.map((s) => (
          <span className="sp-legend__item" key={s.k}>
            <span className="sp-legend__dot" style={{ background: s.color }} />
            {s.label}
          </span>
        ))}
      </div>
      <div className="sp-chart">
        <div className="sp-chart__grid">
          {[0, 1, 2, 3, 4].map((i) => <div key={i} className="sp-chart__gridline" />)}
        </div>
        <div className="sp-chart__bars">
          {USAGE_DAILY.map((d, i) => (
            <div key={i} className="sp-bar">
              {series.map((s, si) => (
                <div
                  key={s.k}
                  className="sp-bar__seg"
                  style={{
                    height: `${(d[s.k] / maxStacked) * H}px`,
                    background: s.color,
                    borderRadius:
                      si === 0 ? "2px 2px 0 0" : si === series.length - 1 ? "0 0 2px 2px" : 0,
                  }}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function RecordsTable({ records, page }) {
  const cols = [
    { k: "time", label: "时间", cls: "sp-col-time" },
    { k: "provider", label: "提供商", cls: "sp-col-provider" },
    { k: "model", label: "模型", cls: "sp-col-model" },
    { k: "input", label: "输入", cls: "sp-col-num" },
    { k: "output", label: "输出", cls: "sp-col-num" },
  ];
  return (
    <div className="sp-surface-card sp-records-card">
      <div className="sp-thead">
        {cols.map((c) => <span key={c.k} className={"sp-th " + c.cls}>{c.label}</span>)}
      </div>
      <div className="sp-divider-h" />
      {records.map((r, i) => (
        <React.Fragment key={i}>
          <div className="sp-trow">
            <span className="sp-td sp-col-time sp-td-time">{r.time}</span>
            <span className="sp-td sp-col-provider sp-td-provider">{r.provider}</span>
            <span className="sp-td sp-col-model sp-td-model">{r.model}</span>
            <span className="sp-td sp-col-num sp-td-num">{r.input}</span>
            <span className="sp-td sp-col-num sp-td-num">{r.output}</span>
          </div>
          <div className="sp-divider-h" />
        </React.Fragment>
      ))}
      {page && (
        <div className="sp-pagination">
          <button type="button" className="sp-page-btn" disabled><Icon name="caret-left" size={14} />上一页</button>
          <span className="sp-page-of">第 {page.current} / {page.total} 页</span>
          <button type="button" className="sp-page-btn"><span>下一页</span><Icon name="caret-right" size={14} /></button>
        </div>
      )}
    </div>
  );
}

// ── 会话 ────────────────────────────────────────────────────────────────────
// 列表 → 下钻单个会话，使用「面板内推进 + 返回」形态。
function UsageSessionsTab({ initialSessionId }) {
  const [openId, setOpenId] = React.useState(initialSessionId || null);
  const session = openId ? SESSION_USAGE[openId] : null;

  if (session) {
    return <SessionDetail session={session} onBack={() => setOpenId(null)} />;
  }
  return (
    <React.Fragment>
      <div className="sp-sec-row">
        <span className="sp-sec-header">会话</span>
        <span className="sp-page-of" style={{ marginLeft: "auto" }}>本月 · 按用量排序</span>
      </div>
      <div style={{ height: "var(--space-md)" }} />
      <div className="sp-surface-card sp-records-card">
        <div className="sp-thead">
          <span className="sp-th sp-col-sess">会话</span>
          <span className="sp-th sp-col-mode">模式</span>
          <span className="sp-th sp-col-model">模型</span>
          <span className="sp-th sp-col-num">词元</span>
          <span className="sp-th sp-col-when">最近使用</span>
        </div>
        <div className="sp-divider-h" />
        {USAGE.topSessions.map((s, i) => (
          <React.Fragment key={s.id}>
            <div className="sp-trow sp-trow--click" onClick={() => setOpenId(s.id)}>
              <span className="sp-td sp-col-sess sp-td-session">{s.title}</span>
              <span className="sp-td sp-col-mode"><span className="sp-top__mode">{s.mode}</span></span>
              <span className="sp-td sp-col-model sp-td-model">{s.model}</span>
              <span className="sp-td sp-col-num sp-td-tok">{s.tokens}</span>
              <span className="sp-td sp-col-when sp-td-time">
                {s.lastUsed}
                <Icon name="caret-right" size={12} className="sp-row-go" />
              </span>
            </div>
            {i < USAGE.topSessions.length - 1 && <div className="sp-divider-h" />}
          </React.Fragment>
        ))}
      </div>
    </React.Fragment>
  );
}

function SessionDetail({ session, onBack }) {
  const total = USAGE_TYPES.reduce((a, t) => a + session.types[t.k], 0);
  const ctx = session.context;
  return (
    <React.Fragment>
      <div className="sp-detail-head">
        <button type="button" className="sp-icon-btn" onClick={onBack} title="返回">
          <Icon name="arrow-left" size={16} />
        </button>
        <div style={{ minWidth: 0 }}>
          <div className="sp-detail-head__title">
            {session.title}
            <span className="sp-top__mode">{session.mode}</span>
          </div>
          <div className="sp-detail-head__sub">
            {session.model} · {session.requests} 次请求 · 最近使用 {session.lastUsed}
          </div>
        </div>
      </div>
      <div style={{ height: "var(--space-3xl)" }} />

      <div className="sp-stat-row">
        <div className="sp-surface-card">
          <div className="sp-stat-card__label">会话用量</div>
          <div className="sp-stat-card__value">
            <span className="sp-stat-card__num">{session.total}</span>
            <span className="sp-stat-card__sub">词元</span>
          </div>
          <div className="sp-dist__stack" style={{ marginTop: "var(--space-2xl)", marginBottom: "var(--space-lg)" }}>
            {USAGE_TYPES.map((t) => (
              <span
                key={t.k}
                className="sp-dist__stack-seg"
                style={{ width: (session.types[t.k] / total) * 100 + "%", background: t.color }}
              />
            ))}
          </div>
          <div className="sp-legend" style={{ margin: 0 }}>
            {USAGE_TYPES.map((t) => (
              <span className="sp-legend__item" key={t.k}>
                <span className="sp-legend__dot" style={{ background: t.color }} />
                {t.label} <b className="sp-legend__val">{session.types[t.k].toFixed(1)}K</b>
              </span>
            ))}
          </div>
        </div>
        <div className="sp-surface-card">
          <div className="sp-stat-card__label">上下文窗口</div>
          <div className="sp-stat-card__value">
            <span className="sp-stat-card__num">{ctx.used}</span>
            <span className="sp-stat-card__sub">/ {ctx.limit} · {ctx.pct}%</span>
          </div>
          <div className="sp-context__bar" style={{ marginTop: "var(--space-2xl)" }}>
            <div className="sp-context__bar-fill" style={{ width: ctx.pct + "%" }} />
          </div>
        </div>
      </div>
      <div style={{ height: "var(--space-4xl)" }} />

      <div className="sp-sec-header">用量构成</div>
      <div style={{ height: "var(--space-md)" }} />
      <div className="sp-surface-card">
        {session.tree.map((n) => (
          <TreeNode node={n} key={n.key || n.name} defaultOpen={n.key === "subagent"} />
        ))}
      </div>
      <div style={{ height: "var(--space-4xl)" }} />

      <div className="sp-sec-header">用量明细</div>
      <div style={{ height: "var(--space-lg)" }} />
      <RecordsTable records={session.records} />
    </React.Fragment>
  );
}

function TreeNode({ node, depth = 0, defaultOpen }) {
  const [open, setOpen] = React.useState(!!defaultOpen);
  const kids = node.kids || node.runs;
  return (
    <div className="sp-tree__node">
      <div
        className={"sp-tree__row" + (kids ? " is-click" : "")}
        onClick={kids ? () => setOpen((o) => !o) : undefined}
      >
        <Icon
          name="caret-right"
          size={11}
          className={"sp-tree__caret" + (kids ? (open ? " is-open" : "") : " is-leaf")}
        />
        <span className="sp-dist__pdot" style={{ background: node.color || SRC_COLOR.subagent }} />
        <span className="sp-tree__name">
          {node.name}
          {node.sub && <span className="sp-tree__sub">{node.sub}</span>}
        </span>
        <span className="sp-dist__track">
          <span
            className="sp-dist__fill"
            style={{ width: parseFloat(node.pct) + "%", background: node.color || SRC_COLOR.subagent }}
          />
        </span>
        <span className="sp-dist__tok">{node.tokens}</span>
        <span className="sp-dist__pct">{node.pct}</span>
      </div>
      {kids && open && (
        <div className="sp-tree__kids">
          {node.kids
            ? node.kids.map((k) => <TreeNode node={k} depth={depth + 1} key={k.name} />)
            : node.runs.map((r, i) => (
                <div className="sp-tree__run" key={i}>
                  <span className="sp-tree__run-time">{r.time}</span>
                  <Icon
                    name={r.ok ? "check" : "warning-circle"}
                    size={11}
                    color={r.ok ? "var(--addition-border)" : "var(--warning-text)"}
                  />
                  <span className="sp-tree__run-label">{r.label}</span>
                  <span className="sp-tree__run-tok">{r.tokens}</span>
                </div>
              ))}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { UsageSection });
