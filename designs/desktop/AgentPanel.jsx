// AgentPanel — agent workflow trace UI. This replaces the simple chat
// panel as the default right-pane in the editor. It shows the agent's
// task list, completion state, and collapsible reasoning between steps.

const AGENT_TRACE = [
  {
    id: "tasks",
    kind: "section",
    icon: "check-circle",
    title: "任务列表",
    progress: "5/5",
    done: true,
  },
  {
    id: "t1",
    kind: "task",
    icon: "plus",
    title: "新建章节",
    subtitle: "新建  星河",
    state: "已完成",
  },
  { id: "r1", kind: "reasoning" },
  {
    id: "t2",
    kind: "task",
    icon: "list-checks",
    title: "已更新任务列表",
    subtitle: "0 pending todos",
    badge: "5",
  },
  { id: "r2", kind: "reasoning" },
  {
    id: "t3",
    kind: "task",
    icon: "paper-plane",
    title: "委派任务",
    subtitle: "委派给  内容核验",
    state: "已完成",
  },
  { id: "r3", kind: "reasoning" },
];

function AgentTaskCard({ item, expanded, onToggle }) {
  const isSection = item.kind === "section";
  return (
    <div className={"m-agent__card" + (isSection ? " m-agent__card--section" : "")}>
      <button type="button" className="m-agent__card-head" onClick={onToggle}>
        <span className={"m-agent__icon" + (item.done ? " is-done" : "")}>
          <Icon name={item.icon} size={14} />
        </span>
        <span className="m-agent__title">
          <span className="m-agent__title-text">{item.title}</span>
          {item.progress && <span className="m-agent__progress">{item.progress}</span>}
          {item.state && <span className="m-pill m-pill--ok">{item.state}</span>}
          {item.badge && <span className="m-agent__badge">{item.badge}</span>}
        </span>
        <Icon
          name="caret-down"
          size={14}
          style={{
            transform: `rotate(${expanded ? 0 : -90}deg)`,
            transition: "transform 180ms ease",
            opacity: 0.5,
          }}
        />
      </button>
      {item.subtitle && (
        <div className="m-agent__subtitle">{item.subtitle}</div>
      )}
    </div>
  );
}

function ReasoningCard({ expanded, onToggle }) {
  return (
    <div className="m-agent__card m-agent__card--reasoning">
      <button type="button" className="m-agent__card-head" onClick={onToggle}>
        <span className="m-agent__icon m-agent__icon--reasoning">
          <Icon name="circles-three" size={14} />
        </span>
        <span className="m-agent__title">
          <span className="m-agent__title-text" style={{ color: "var(--text-muted)" }}>
            推理过程
          </span>
        </span>
        <Icon
          name="caret-down"
          size={14}
          style={{
            transform: `rotate(${expanded ? 0 : -90}deg)`,
            transition: "transform 180ms ease",
            opacity: 0.5,
          }}
        />
      </button>
      {expanded && (
        <div className="m-agent__reasoning-body">
          <p>
            根据当前章节大纲和已有的人物档案，AI 需要先确定第一章的叙事起点。林远是主角，
            他的初始状态是「失业 · 自我怀疑」，但不能在开篇就直接告白这个状态，需要通过环境
            和细节让读者自己感受到。
          </p>
          <p>
            选择从「第十七次刷新招聘网站」入手，把数字作为叙事钩子；通过室友状态对比的一句话
            完成主角处境的快速交代；再用陈浩的微信打破他的发呆，进入主线（VR / 游戏）。
          </p>
        </div>
      )}
    </div>
  );
}

function AgentPanel({ onClose, onSwitchPane }) {
  const [expanded, setExpanded] = React.useState({
    tasks: true,
    t1: true,
    r1: false,
    t2: true,
    r2: false,
    t3: true,
    r3: false,
  });
  const toggle = (id) => setExpanded((p) => ({ ...p, [id]: !p[id] }));

  return (
    <aside className="m-agent">
      <div className="m-agent__head">
        <div className="m-agent__head-l">
          <span className="m-agent__head-icon">
            <Icon name="sparkle" size={14} />
          </span>
          <div className="m-agent__head-meta">
            <div className="m-agent__head-title">开始写第一卷 + 第一章</div>
            <div className="m-agent__head-sub">
              最强写手 · 自定义供应商
              {" · "}mimo‑v2.5‑…
            </div>
          </div>
        </div>
        <div className="m-agent__head-r">
          {onSwitchPane && (
            <button className="m-icon-btn" title="对话模式" onClick={onSwitchPane}>
              <Icon name="chat-circle-text" size={14} />
            </button>
          )}
          <button className="m-icon-btn" title="全屏">
            <Icon name="arrows-out" size={14} />
          </button>
          <button className="m-icon-btn" title="编辑提示">
            <Icon name="pencil-simple" size={14} />
          </button>
          <button className="m-icon-btn" title="关闭" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>

      <div className="m-agent__scroll">
        {AGENT_TRACE.map((item) =>
          item.kind === "reasoning" ? (
            <ReasoningCard
              key={item.id}
              expanded={expanded[item.id]}
              onToggle={() => toggle(item.id)}
            />
          ) : (
            <AgentTaskCard
              key={item.id}
              item={item}
              expanded={expanded[item.id]}
              onToggle={() => toggle(item.id)}
            />
          )
        )}

        <div className="m-agent__md">
          <div className="m-agent__md-rule" />
          <h2 className="m-agent__md-h2"><span style={{color:"var(--success)"}}>✓</span> 第一章创作完成</h2>
          <h3 className="m-agent__md-h3">已完成内容</h3>
          <ul className="m-agent__md-list">
            <li>第一卷《新世界的钥匙》大纲已写入</li>
            <li>第 01 章「新的开始」初稿 (4,210 字)</li>
            <li>主角林远的角色档案首版</li>
            <li>VR 设定与游戏「星河」世界基线</li>
          </ul>
        </div>
      </div>

      <div className="m-composer m-composer--rail">
        <div className="m-composer__field">
          <textarea
            className="m-composer__input"
            rows={2}
            placeholder={'继续指示——例如 "开始写第二章"…'}
            spellCheck={false}
          />
        </div>
        <div className="m-composer__toolbar">
          <div className="m-composer__tools">
            <button className="m-icon-btn" title="附件">
              <Icon name="paperclip" size={14} />
            </button>
            <button className="m-icon-btn" title="技能">
              <Icon name="magic-wand" size={14} />
            </button>
          </div>
          <ComposerModelSelect initial="mimo-v2.5 · 默认" />
          <button className="m-btn m-btn--primary m-btn--sm">
            <Icon name="paper-plane" size={14} />
            继续
          </button>
        </div>
      </div>
    </aside>
  );
}

Object.assign(window, { AgentPanel });
