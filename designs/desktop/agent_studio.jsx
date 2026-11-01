// agent_studio.jsx — 「智能体」页面拆分后的两个 Home 主区页面:
//   1. 模型设置(ModelSettingsPage) — 内置对话 subagent,不可删除,只配运行模型。
//   2. 专家团(ExpertTeamPage)     — 官方内置议会专家 + 我的自定义专家 + 广场安装。
//
// 对应真实代码:
//   智能体 = SubAgent(lib/shared/models/subagent.dart, mode chat/council)。
//   内置不可删名单 = builtinSubAgentSlugs(lib/shared/services/ai/builtin_agent_tools.dart)。
//   种子名称/描述 = lib/shared/services/initialization/subagent_seeds.dart。
//   模型目录 = lib/shared/models/models_catalog.dart(取真实 ID:mimo/fable/gpt-5.6…)。
//   广场沿用 Agent Skill 市场形态(lib/desktop/features/agent_skills)。
//
// 拆分口径(已与用户确认):
//   模型设置 = 4 个对话流程 subagent(writer/review/style_polish/explorer),只配模型。
//   专家团   = 6 个议会专家作为「官方专家」(不可删) + 我的专家(自定义) + 广场。
//
// 复用:全局 Icon(Icon.jsx)、m-select / m-mgmt / m-mgmt-card / m-mgmt-tag /
//   m-btn / m-switch / m-chip / sk-tabs / sk-toolbar / sk-toast 样式。新增样式在
//   agent_studio.css(as- 前缀)。text/babel 各脚本独立作用域,原子在本文件内定义。

/* ============================ mock data ============================ */

// 真实模型 ID(models_catalog.dart)+ 展示名/供应商图标。
const AS_MODELS = [
  { id: "mimo-v2.5-pro", name: "mimo-v2.5-pro", provider: "自定义供应商", icon: "sparkle" },
  { id: "mimo-v2.5", name: "mimo-v2.5", provider: "自定义供应商", icon: "sparkle" },
  { id: "claude-fable-5", name: "Claude Fable 5", provider: "Anthropic", icon: "diamond" },
  { id: "claude-sonnet-5", name: "Claude Sonnet 5", provider: "Anthropic", icon: "diamond" },
  { id: "claude-opus-4-8", name: "Claude Opus 4.8", provider: "Anthropic", icon: "diamond" },
  { id: "gpt-5.6", name: "GPT-5.6", provider: "OpenAI", icon: "robot" },
  { id: "gpt-5.6-sol", name: "GPT-5.6 Sol", provider: "OpenAI", icon: "robot" },
  { id: "gpt-5.6-terra", name: "GPT-5.6 Terra", provider: "OpenAI", icon: "robot" },
  { id: "gpt-5.6-luna", name: "GPT-5.6 Luna", provider: "OpenAI", icon: "robot" },
  { id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "DeepSeek", icon: "brain" },
  { id: "gemini-3.1-pro", name: "Gemini 3.1 Pro", provider: "Google", icon: "sparkle" },
];
const AS_MODEL_BY_ID = Object.fromEntries(AS_MODELS.map((m) => [m.id, m]));

// 图像生成模型目录(与文本模型分开)。
const AS_IMAGE_MODELS = [
  { id: "gpt-image-1", name: "GPT Image 1", provider: "OpenAI", icon: "robot" },
  { id: "seedream-4", name: "Seedream 4.0", provider: "Doubao", icon: "sparkle" },
  { id: "nano-banana-2", name: "Nano Banana 2", provider: "Google", icon: "sparkle" },
];

// 模型设置 — 4 个内置对话流程 subagent(builtin,不可删)。
const AS_FLOW = [
  {
    slug: "writer", name: "正文写作", emoji: "✍️", modelId: "mimo-v2.5-pro",
    description: "专精长篇网文正文创作与写入,适合连续 4 章及以上的批量写作委派。",
  },
  {
    slug: "review", name: "内容审查", emoji: "🔍", modelId: "gpt-5.6-sol",
    description: "核验情节逻辑、角色一致性、世界观规则及用户自定义规则的符合度。",
  },
  {
    slug: "style_polish", name: "文风润色", emoji: "✨", modelId: "claude-sonnet-5",
    description: "提升文笔流畅度、节奏和画面感,不改变剧情事实。",
  },
  {
    slug: "explorer", name: "内容检索", emoji: "🧭", modelId: "gpt-5.6-terra",
    description: "搜索互联网、读取网页、浏览内部资料,收集所需的信息和素材。",
  },
  {
    slug: "chronicler", name: "事实梳理", emoji: "🗓️", modelId: "gpt-5.6-luna",
    description: "提取章节关键事实、核验连续性并归档为事实台账,为后续写作与审查提供一致的事实基线。",
  },
];

// 基础模型 — 聊天对话(文本)与图像生成两类,放在内置智能体上方。
const AS_BASE = [
  {
    slug: "chat", name: "聊天对话", emoji: "💬", modelId: "gpt-5.6",
    description: "主对话与直接问答默认使用的文本模型;未单独指定的智能体也回退到它。",
  },
  {
    slug: "image", name: "图像生成", emoji: "🎨", modelId: "gpt-image-1", image: true,
    description: "生成角色、场景、封面等图片素材。",
  },
];

// 专家团 · 官方专家 — 6 个内置议会专家(builtin,不可删,可停用/配模型)。
const AS_OFFICIAL = [
  {
    id: "off-plot", slug: "plot_architect", name: "剧情架构师", emoji: "🏗️", category: "结构",
    mode: "council", modelId: "claude-fable-5", enabled: true,
    description: "分析剧情结构、伏笔布局和高潮设计,指出大纲中悬而未决的伏笔与动机断层。",
  },
  {
    id: "off-char", slug: "character_analyst", name: "角色分析师", emoji: "🎭", category: "角色",
    mode: "council", modelId: "claude-fable-5", enabled: true,
    description: "分析角色动机、成长弧线和人际关系,守护每个角色的立场与逻辑一致。",
  },
  {
    id: "off-world", slug: "world_builder", name: "世界观构建师", emoji: "🌍", category: "设定",
    mode: "council", modelId: "claude-sonnet-5", enabled: true,
    description: "维护世界观一致性,补充设定细节,核查地理、器物、制度与时间线冲突。",
  },
  {
    id: "off-pacing", slug: "pacing_expert", name: "叙事节奏师", emoji: "🥁", category: "节奏",
    mode: "council", modelId: "gpt-5.6", enabled: true,
    description: "评估叙事节奏和紧张感平衡,标出节奏塌陷与信息释放过密的段落。",
  },
  {
    id: "off-conflict", slug: "conflict_designer", name: "冲突设计师", emoji: "⚔️", category: "张力",
    mode: "council", modelId: "claude-sonnet-5", enabled: false,
    description: "设计冲突与对抗以增强故事张力,规划矛盾升级与爆发落点。",
  },
  {
    id: "off-theme", slug: "theme_guardian", name: "主题守护者", emoji: "🛡️", category: "主题",
    mode: "council", modelId: "gpt-5.6", enabled: true,
    description: "确保故事主题贯穿始终,提示偏离主题的情节与表达。",
  },
];

// 专家团 · 我的专家 — 用户自定义 subagent。
const AS_MINE = [
  {
    id: "mine-voice", slug: "character_voice", name: "人物声音", emoji: "🗣️", category: "对白",
    modelId: "mimo-v2.5-pro", enabled: true, mode: "chat",
    description: "守护每个角色的语气一致性,根据人物档案校验对白是否符合身份、年龄与处境。",
  },
  {
    id: "mine-lore", slug: "lore_audit", name: "世界观考据", emoji: "📜", category: "设定考据",
    modelId: "claude-sonnet-5", enabled: false, mode: "council",
    description: "对照世界观设定与历史背景,核查正文中的地理、器物、制度、时间线是否前后自洽。",
  },
];

// 专家团 · 广场 — 社区/官方上传,可安装。含议会/执行两类。
const AS_MARKET = [
  {
    id: "mk-golden", name: "网文黄金三章", emoji: "🪝", author: "老猫", installs: 3280,
    version: "2.1.0", category: "结构", mode: "council",
    description: "按网文黄金三章模型重排开篇节奏:悬念前置、爽点密度、章末钩子。适合男频长篇。",
  },
  {
    id: "mk-multi", name: "多线叙事编排", emoji: "🕸️", author: "青梧", installs: 1470,
    version: "1.3.0", category: "结构", mode: "council",
    description: "梳理多线叙事的时间轴与交汇点,标出信息释放与视角切换节奏。",
  },
  {
    id: "mk-mystery", name: "悬疑埋雷官", emoji: "🧩", author: "夜航船", installs: 962,
    version: "1.0.2", category: "结构", mode: "council",
    description: "为悬疑线规划线索埋设与回收点,校验反转是否有据可循、是否提前泄底。",
  },
  {
    id: "mk-military", name: "军事考据官", emoji: "⚙️", author: "幻界官方", official: true, installs: 1840,
    version: "1.2.0", category: "设定", mode: "council",
    description: "核查冷兵器/近代战争的编制、装备、战术与后勤细节,避免硬伤。",
  },
  {
    id: "mk-expand", name: "扩写快手", emoji: "🚀", author: "快刀", installs: 2760,
    version: "1.4.0", category: "结构", mode: "chat",
    description: "把大纲或短段扩写为流畅正文,承接既定风格与人物声音,适合批量委派。",
  },
  {
    id: "mk-dialogue", name: "对白顺化师", emoji: "💬", author: "语生", installs: 1930,
    version: "1.1.0", category: "对白", mode: "chat",
    description: "打磨对白语气、停顿与潜台词,让每个角色说话有辨识度,不改动剧情。",
  },
];

const AS_CATEGORIES = ["结构", "角色", "设定", "节奏", "张力", "主题", "对白", "文风"];

/* ============================ atoms ============================ */

function AsSwitch({ on, onChange }) {
  return (
    <button
      type="button"
      className={"m-switch" + (on ? " is-on" : "")}
      onClick={(e) => { e.stopPropagation(); onChange(!on); }}
      role="switch"
      aria-checked={on}
    >
      <span className="m-switch__knob" />
    </button>
  );
}

function AsTag({ icon, tone, children }) {
  return (
    <span className={"m-mgmt-tag" + (tone ? " m-mgmt-tag--" + tone : "")}>
      {icon && <Icon name={icon} size={12} />}
      {children}
    </span>
  );
}

// 模型选择器 — 复用 m-select 视觉,展示真实模型目录(按 provider 副标题)。
// compact = 卡片底部内嵌的小尺寸变体。
function StudioModelSelect({ initial, compact, models = AS_MODELS }) {
  const [selectedId, setSelectedId] = React.useState(initial);
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  const selected = models.find((m) => m.id === selectedId);

  React.useEffect(() => {
    if (!open) { return; }
    const onDown = (e) => {
      if (ref.current && !ref.current.contains(e.target)) { setOpen(false); }
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  return (
    <div
      className={"m-select-wrap as-model-select" + (compact ? " as-model-select--compact" : "") + (open ? " is-open" : "")}
      ref={ref}
    >
      <button
        type="button"
        className="m-select as-model-select__btn"
        onClick={(e) => { e.stopPropagation(); setOpen((o) => !o); }}
      >
        {selected && <Icon name={selected.icon} size={14} className="as-model-select__lead" />}
        <span className={selected ? "" : "m-select__placeholder"}>
          {selected ? selected.name : "未选择模型"}
        </span>
        <Icon name="caret-down" size={13} className="m-select__caret" style={{ opacity: 0.5 }} />
      </button>
      {open && (
        <div className="m-select__menu as-model-select__menu" role="menu">
          {models.map((m) => {
            const isSel = selectedId === m.id;
            return (
              <button
                key={m.id}
                type="button"
                className={"m-select__item" + (isSel ? " is-selected" : "")}
                onClick={(e) => { e.stopPropagation(); setSelectedId(m.id); setOpen(false); }}
              >
                <Icon name={m.icon} size={18} className="m-select__item-icon" />
                <span className="m-select__item-meta">
                  <span className="m-select__item-name">{m.name}</span>
                  <span className="m-select__item-provider">{m.provider}</span>
                </span>
                {isSel && <Icon name="check" size={18} className="m-select__item-check" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function useToast() {
  const [toast, setToast] = React.useState(null);
  React.useEffect(() => {
    if (!toast) { return; }
    const t = setTimeout(() => setToast(null), 2000);
    return () => clearTimeout(t);
  }, [toast]);
  return [toast, setToast];
}

/* ============================ 模型设置 ============================ */

function AsRoleRow({ item }) {
  return (
    <div className="as-role-row">
      <div className="m-mgmt-card__avatar as-role-row__avatar">
        <span className="m-mgmt-card__avatar-emoji">{item.emoji}</span>
      </div>
      <div className="as-role-row__meta">
        <div className="as-role-row__title-line">
          <span className="as-role-row__name">{item.name}</span>
        </div>
        <p className="as-role-row__desc">{item.description}</p>
      </div>
      <div className="as-role-row__model">
        <span className="as-role-row__model-label">模型</span>
        <StudioModelSelect initial={item.modelId} models={item.image ? AS_IMAGE_MODELS : AS_MODELS} />
      </div>
    </div>
  );
}

function ModelSettingsPage({ onGotoExperts }) {
  return (
    <div className="m-mgmt as-model-settings">
      <header className="m-mgmt__head">
        <span className="m-mgmt__head-icon">
          <Icon name="sliders-horizontal" size={18} />
        </span>
        <div className="m-mgmt__head-meta">
          <div className="m-mgmt__title">模型设置</div>
        </div>
        <button type="button" className="m-btn m-btn--text m-btn--sm">
          <Icon name="arrow-counter-clockwise" size={14} />
          恢复默认
        </button>
      </header>

      <div className="m-mgmt__scroll">
        <div className="as-role-list">
          {[...AS_BASE, ...AS_FLOW].map((it) => (
            <AsRoleRow key={it.slug} item={it} />
          ))}
        </div>
      </div>
    </div>
  );
}

/* ============================ 专家团 ============================ */

// 通用卡片外壳 — head(avatar+name+badges+右上角) + desc + footer。
function AsCard({ item, badges, foot, kebab, onKebab, kebabMenu }) {
  return (
    <article className="as-card">
      <div className="as-card__head">
        <div className="m-mgmt-card__avatar as-card__avatar">
          <span className="m-mgmt-card__avatar-emoji">{item.emoji}</span>
          <span
            className={"as-type-dot " + (item.mode === "council" ? "as-type-dot--council" : "as-type-dot--exec")}
            title={item.mode === "council" ? "议会专家" : "执行专家"}
          >
            <Icon name={item.mode === "council" ? "users-three" : "lightning"} size={9} />
          </span>
        </div>
        <div className="as-card__title-wrap">
          <div className="as-card__title">{item.name}</div>
          <div className="as-card__badges">{badges}</div>
        </div>
        {kebab && (
          <div className="as-kebab">
            <button type="button" className="m-icon-btn" onClick={(e) => { e.stopPropagation(); onKebab(); }}>
              <Icon name="dots-three" size={16} />
            </button>
            {kebab === "open" && <div className="as-kebab__menu" role="menu">{kebabMenu}</div>}
          </div>
        )}
      </div>
      <p className="as-card__desc">{item.description}</p>
      <div className="as-card__foot">{foot}</div>
    </article>
  );
}

function OfficialCard({ item, onToggle, kebabOpen, onKebab, flash }) {
  return (
    <AsCard
      item={item}
      kebab={kebabOpen ? "open" : "closed"}
      onKebab={() => onKebab(kebabOpen ? null : item.id)}
      kebabMenu={
        <React.Fragment>
          <button type="button" onClick={() => { onKebab(null); flash("已重置为内置提示词。"); }}>
            <Icon name="arrow-counter-clockwise" size={15} />重置提示词
          </button>
          <button type="button" onClick={() => { onKebab(null); flash("已另存到我的专家。"); }}>
            <Icon name="copy" size={15} />另存为我的专家
          </button>
        </React.Fragment>
      }
      badges={<AsTag>{item.category}</AsTag>}
      foot={
        <React.Fragment>
          <StudioModelSelect initial={item.modelId} compact />
          <span className="as-card__foot-spacer" />
          <span className="as-card__provider"><Icon name="seal-check" size={13} />官方</span>
          <AsSwitch on={item.enabled} onChange={() => onToggle(item.id)} />
        </React.Fragment>
      }
    />
  );
}

function MineCard({ item, onToggle, kebabOpen, onKebab, flash }) {
  return (
    <AsCard
      item={item}
      kebab={kebabOpen ? "open" : "closed"}
      onKebab={() => onKebab(kebabOpen ? null : item.id)}
      kebabMenu={
        <React.Fragment>
          <button type="button" onClick={() => { onKebab(null); flash("编辑专家(mock)。"); }}>
            <Icon name="pencil-simple" size={15} />编辑
          </button>
          <button type="button" onClick={() => { onKebab(null); flash("已上传到广场,待审核。"); }}>
            <Icon name="storefront" size={15} />上传到广场
          </button>
          <button type="button" className="is-danger" onClick={() => { onKebab(null); flash("已删除专家。"); }}>
            <Icon name="trash-simple" size={15} />删除
          </button>
        </React.Fragment>
      }
      badges={<AsTag>{item.category}</AsTag>}
      foot={
        <React.Fragment>
          <StudioModelSelect initial={item.modelId} compact />
          <span className="as-card__foot-spacer" />
          <span className="as-card__provider as-card__provider--mine"><Icon name="note-pencil" size={13} />自定义</span>
          <AsSwitch on={item.enabled} onChange={() => onToggle(item.id)} />
        </React.Fragment>
      }
    />
  );
}

function MarketCard({ item, onInstall }) {
  return (
    <AsCard
      item={item}
      badges={
        <React.Fragment>
          {item.official
            ? <AsTag icon="seal-check" tone="accent">官方</AsTag>
            : <AsTag icon="user" tone="muted">{item.author}</AsTag>}
          <AsTag>{item.category}</AsTag>
        </React.Fragment>
      }
      foot={
        <React.Fragment>
          <span className="as-card__stamp"><Icon name="download-simple" size={12} />{item.installs.toLocaleString()}</span>
          <AsTag icon="git-fork" tone="muted">v{item.version}</AsTag>
          <span className="as-card__foot-spacer" />
          <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={() => onInstall(item)}>
            <Icon name="download-simple" size={14} />安装
          </button>
        </React.Fragment>
      }
    />
  );
}

const AS_TABS = [
  { id: "mine", label: "我的专家" },
  { id: "official", label: "官方专家" },
  { id: "market", label: "广场" },
];

// 分区 — 每个 tab 内按 议会专家 / 执行专家 分段。空段(且无 force)不渲染,
// mode 归属由段头统一表达,卡片不再逐个打「议会/对话」徽章。
function ExpertSection({ label, count, force, children }) {
  const arr = React.Children.toArray(children).filter(Boolean);
  if (arr.length === 0 && !force) { return null; }
  return (
    <div className="as-section">
      <div className="m-mgmt__section-label">
        {label}<span className="m-mgmt__count">· {count}</span>
      </div>
      <div className="m-mgmt__grid">{children}</div>
    </div>
  );
}

function ExpertTeamPage() {
  const [tab, setTab] = React.useState("mine");
  const [official, setOfficial] = React.useState(() => AS_OFFICIAL.map((o) => ({ ...o })));
  const [mine, setMine] = React.useState(() => AS_MINE.map((o) => ({ ...o })));
  const [query, setQuery] = React.useState("");
  const [cat, setCat] = React.useState("全部");
  const [kebab, setKebab] = React.useState(null);
  const [toast, flash] = useToast();

  const toggleOfficial = (id) =>
    setOfficial((l) => l.map((o) => (o.id === id ? { ...o, enabled: !o.enabled } : o)));
  const toggleMine = (id) =>
    setMine((l) => l.map((o) => (o.id === id ? { ...o, enabled: !o.enabled } : o)));

  const applyFilter = (arr) => {
    const q = query.trim().toLowerCase();
    return arr.filter((it) => {
      if (cat !== "全部" && it.category !== cat) { return false; }
      if (!q) { return true; }
      return [it.name, it.description, it.author].some((s) => s && s.toLowerCase().includes(q));
    });
  };

  const counts = { official: official.length, mine: mine.length, market: AS_MARKET.length };
  const officialList = applyFilter(official);
  const mineList = applyFilter(mine);
  const marketList = applyFilter(AS_MARKET);

  return (
    <div className="m-mgmt as-experts" onClick={() => kebab && setKebab(null)}>
      <header className="m-mgmt__head">
        <span className="m-mgmt__head-icon">
          <Icon name="users-three" size={18} />
        </span>
        <div className="m-mgmt__head-meta">
          <div className="m-mgmt__title">专家团</div>
          <div className="m-mgmt__sub">内置官方专家、你的自定义专家与广场安装组成的智能体团队,可在对话与议会中协作。</div>
        </div>
        <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={() => flash("从文件导入专家(mock)。")}>
          <Icon name="download-simple" size={14} />导入
        </button>
        <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={() => flash("新建自定义专家(mock)。")}>
          <Icon name="plus" size={14} />创建专家
        </button>
      </header>

      <nav className="sk-tabs as-tabs">
        {AS_TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            className={"sk-tab" + (tab === t.id ? " is-active" : "")}
            onClick={() => setTab(t.id)}
          >
            {t.label}
            <span className="sk-tab__count">{counts[t.id]}</span>
          </button>
        ))}
      </nav>

      <div className="sk-toolbar as-toolbar">
        <div className="sk-search">
          <Icon name="magnifying-glass" size={13} style={{ opacity: 0.5 }} />
          <input
            className="sk-search__input"
            placeholder="搜索专家"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            spellCheck={false}
          />
        </div>
        <div className="sk-filter">
          <Icon name="funnel" size={13} style={{ opacity: 0.6 }} />
          {["全部", ...AS_CATEGORIES].map((c) => (
            <button
              key={c}
              type="button"
              className={"m-chip" + (cat === c ? " m-chip--brass" : "")}
              onClick={() => setCat(c)}
            >
              {c}
            </button>
          ))}
        </div>
      </div>

      <div className="m-mgmt__scroll as-experts__scroll">
        {tab === "official" && (
          <React.Fragment>
            <div className="as-hint">
              <Icon name="info" size={13} />
              官方专家为内置议会专家,不可删除,可停用或为其单独指定模型。
            </div>
            <ExpertSection label="议会专家" count={officialList.length}>
              {officialList.map((it) => (
                <OfficialCard
                  key={it.id}
                  item={it}
                  onToggle={toggleOfficial}
                  kebabOpen={kebab === it.id}
                  onKebab={setKebab}
                  flash={flash}
                />
              ))}
            </ExpertSection>
          </React.Fragment>
        )}

        {tab === "mine" && (() => {
          const council = mineList.filter((i) => i.mode === "council");
          const exec = mineList.filter((i) => i.mode !== "council");
          const showCreate = cat === "全部" && !query.trim();
          const mineCard = (it) => (
            <MineCard
              key={it.id}
              item={it}
              onToggle={toggleMine}
              kebabOpen={kebab === it.id}
              onKebab={setKebab}
              flash={flash}
            />
          );
          return (
            <React.Fragment>
              <ExpertSection label="议会专家" count={council.length}>
                {council.map(mineCard)}
              </ExpertSection>
              <ExpertSection label="执行专家" count={exec.length} force={showCreate}>
                {exec.map(mineCard)}
                {showCreate && (
                  <button
                    type="button"
                    className="m-mgmt-card m-mgmt-card--create as-create-card"
                    onClick={() => flash("新建自定义专家(mock)。")}
                  >
                    <span className="m-mgmt-card__create-plus"><Icon name="plus" size={20} /></span>
                    <span className="m-mgmt-card__create-label">创建自定义专家</span>
                  </button>
                )}
              </ExpertSection>
            </React.Fragment>
          );
        })()}

        {tab === "market" && (() => {
          const council = marketList.filter((i) => i.mode === "council");
          const exec = marketList.filter((i) => i.mode !== "council");
          const mkCard = (it) => (
            <MarketCard
              key={it.id}
              item={it}
              onInstall={(m) => flash(`已安装“${m.name}”到我的专家。`)}
            />
          );
          return (
            <React.Fragment>
              <ExpertSection label="议会专家" count={council.length}>
                {council.map(mkCard)}
              </ExpertSection>
              <ExpertSection label="执行专家" count={exec.length}>
                {exec.map(mkCard)}
              </ExpertSection>
            </React.Fragment>
          );
        })()}
      </div>

      {toast && (
        <div className="sk-toast">
          <Icon name="check-circle" size={15} />
          {toast}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { ModelSettingsPage, ExpertTeamPage });
