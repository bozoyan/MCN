// Home AI management grid pages. The sidebar's flat AI nav items (提示词 /
// 智能体 / 智能体技能 / 快捷方式) now open these card-grid pages in the main
// pane — replacing the old collapsible inline lists. Mirrors:
//   lib/desktop/pages/home_agent_management_lists.dart
//   lib/desktop/widgets/agent_management/home_management_cards.dart
// Header (icon + title + subtitle + search + 新建) → section label + count →
// medium card grid (avatar/badge + title + 2-line desc + meta tags) → dotted
// 新建 card. Card right-click is a delete affordance in Flutter; here the
// hover row-action stands in for it.

// ---- Per-kind config -----------------------------------------------------
// Each AI nav target maps to: its data list, header chrome, the entity
// content type to open on card-tap, and how each card renders.
const MGMT_KINDS = {
  agentProfile: {
    entityType: "agentProfile",
    icon: "tree-structure",
    title: "提示词",
    subtitle: "项目主笔的提示词配置，决定 AI 落笔时的身份与笔法。",
    sectionLabel: "全局",
    // Agent profiles aren't user-creatable from Home (only the primary one).
    createLabel: null,
    emptyText: "暂无提示词",
    items: (D) => D.agents,
    leading: (a) => <MgmtAvatar emoji={a.emoji} icon={a.icon || "tree-structure"} />,
    title_: (a) => a.name,
    desc: (a) => a.description || a.subtitle,
    meta: (a) => [
      { icon: "globe", label: "全局" },
      { icon: "note-pencil", label: a.role || "写作" },
    ],
  },
  subagent: {
    entityType: "subagent",
    icon: "robot",
    title: "智能体",
    subtitle: "在对话与议会中协作的子智能体，各司其职、独立发声。",
    sectionLabel: "全局",
    createLabel: "新建智能体",
    emptyText: "暂无子智能体",
    items: (D) => D.subagents,
    leading: (a) => <MgmtAvatar emoji={a.emoji} icon={a.icon || "robot"} />,
    title_: (a) => a.name,
    desc: (a) => a.description,
    meta: (a) => [
      { icon: "globe", label: "全局" },
      a.mode === "council"
        ? { icon: "users-three", label: "议会" }
        : { icon: "chat-circle-text", label: "对话" },
      a.enabled
        ? { icon: "check-circle", label: "已启用", tone: "success" }
        : { icon: "warning-circle", label: "已停用", tone: "muted" },
    ],
  },
  skill: {
    entityType: "skill",
    icon: "sparkle",
    title: "智能体技能",
    subtitle: "可随时调用的写作技能，把你反复用到的手法固化下来。",
    sectionLabel: "全局",
    createLabel: "新建技能",
    emptyText: "暂无技能",
    items: (D) => D.skills,
    leading: () => <MgmtBadge icon="sparkle" />,
    title_: (s) => s.name,
    desc: (s) => s.description || s.whenToUse,
    meta: (s) => [
      { icon: "globe", label: "全局" },
      s.builtin
        ? { icon: "check-circle", label: "内置", tone: "accent" }
        : { icon: "note-pencil", label: "自定义" },
      s.enabled
        ? { icon: "check-circle", label: "已启用", tone: "success" }
        : { icon: "warning-circle", label: "已停用", tone: "muted" },
    ],
  },
  shortcut: {
    entityType: "shortcut",
    icon: "cursor-click",
    title: "快捷方式",
    subtitle: "选中文字后一键触发的常用动作，扩写、润色、续写。",
    sectionLabel: "全部",
    createLabel: "新建快捷方式",
    emptyText: "暂无快捷方式",
    items: (D) => D.shortcuts,
    leading: () => <MgmtBadge icon="cursor-click" />,
    title_: (s) => s.name,
    desc: (s) => s.description,
    meta: (s) => [
      s.builtin
        ? { icon: "check-circle", label: "内置", tone: "accent" }
        : { icon: "note-pencil", label: "自定义" },
      s.enabled
        ? { icon: "check-circle", label: "已启用", tone: "success" }
        : { icon: "warning-circle", label: "已停用", tone: "muted" },
    ],
  },
};

// Avatar — emoji on a tonal tile, or a fallback phosphor icon. Mirrors
// AgentAvatar in the agent/subagent cards.
function MgmtAvatar({ emoji, icon }) {
  return (
    <div className="m-mgmt-card__avatar">
      {emoji ? <span className="m-mgmt-card__avatar-emoji">{emoji}</span> : <Icon name={icon} size={20} />}
    </div>
  );
}

// Accent-tinted icon badge — HomeManagementIconBadge.
function MgmtBadge({ icon }) {
  return (
    <div className="m-mgmt-card__badge">
      <Icon name={icon} size={18} />
    </div>
  );
}

// HomeManagementMetaTag — small pill; `tone` lifts status tags.
function MetaTag({ icon, label, tone }) {
  return (
    <span className={"m-mgmt-tag" + (tone ? " m-mgmt-tag--" + tone : "")}>
      <Icon name={icon} size={12} />
      {label}
    </span>
  );
}

function MgmtCard({ cfg, item, onOpen }) {
  return (
    <article className="m-mgmt-card" onClick={() => onOpen(item)} role="button" tabIndex={0}>
      <div className="m-mgmt-card__head">
        {cfg.leading(item)}
        <div className="m-mgmt-card__title">{cfg.title_(item)}</div>
        <Icon name="caret-right" size={15} className="m-mgmt-card__go" />
      </div>
      <p className="m-mgmt-card__desc">{cfg.desc(item)}</p>
      <div className="m-mgmt-card__meta">
        {cfg.meta(item).map((m, i) => (
          <MetaTag key={i} icon={m.icon} label={m.label} tone={m.tone} />
        ))}
      </div>
    </article>
  );
}

// HomeCreateManagementCard — dotted-border tile that opens a fresh draft.
function CreateCard({ label, onCreate }) {
  return (
    <button type="button" className="m-mgmt-card m-mgmt-card--create" onClick={onCreate}>
      <span className="m-mgmt-card__create-plus">
        <Icon name="plus" size={20} />
      </span>
      <span className="m-mgmt-card__create-label">{label}</span>
    </button>
  );
}

function ManagementGridView({ kind, onOpen, onCreate }) {
  const cfg = MGMT_KINDS[kind];
  const D = window.REVERIC_DATA;
  const [query, setQuery] = React.useState("");

  const all = cfg.items(D);
  const q = query.trim().toLowerCase();
  const items = q
    ? all.filter((it) =>
        [cfg.title_(it), cfg.desc(it)].some(
          (s) => s && s.toLowerCase().includes(q)
        )
      )
    : all;

  const openDraft = () =>
    onCreate({ type: cfg.entityType, entity: { id: "new-" + kind, isNew: true } });

  return (
    <div className="m-mgmt">
      <header className="m-mgmt__head">
        <span className="m-mgmt__head-icon">
          <Icon name={cfg.icon} size={18} />
        </span>
        <div className="m-mgmt__head-meta">
          <div className="m-mgmt__title">{cfg.title}</div>
          <div className="m-mgmt__sub">{cfg.subtitle}</div>
        </div>
        <div className="m-mgmt__search">
          <Icon name="magnifying-glass" size={13} style={{ opacity: 0.5 }} />
          <input
            className="m-mgmt__search-input"
            placeholder={"搜索" + cfg.title}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            spellCheck={false}
          />
        </div>
        {cfg.createLabel && (
          <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={openDraft}>
            <Icon name="plus" size={14} />
            {cfg.createLabel}
          </button>
        )}
      </header>

      <div className="m-mgmt__scroll">
        <div className="m-mgmt__section-label">
          {cfg.sectionLabel}
          <span className="m-mgmt__count">· {items.length}</span>
        </div>

        {items.length === 0 && q ? (
          <div className="m-mgmt__empty">
            <Icon name="magnifying-glass" size={28} style={{ opacity: 0.4 }} />
            <div className="m-mgmt__empty-text">没有匹配“{query}”的结果</div>
          </div>
        ) : (
          <div className="m-mgmt__grid">
            {items.map((it) => (
              <MgmtCard key={it.id} cfg={cfg} item={it} onOpen={onOpen} />
            ))}
            {cfg.createLabel && !q && (
              <CreateCard label={cfg.createLabel} onCreate={openDraft} />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { ManagementGridView, MGMT_KINDS });
