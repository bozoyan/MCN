// NavRail — leftmost icon + label nav.
// Sections: 系统 · 创作 · 世界观 · AI · 灵感. Bottom: brand row "幻界".
// 分组、顺序与图标对齐 lib/desktop/widgets/sidebar/rail.dart 的 _railGroups：
// 素材归「创作」、封面归「系统」,势力/生物/物品/技能并成一个「图鉴」入口,
// 没有单独的「资料」组。普通 novel 与剧本共用这套骨架,只有「创作」组的内容不同。
// 全局搜索已改为悬浮入口,不再在 rail 里占一格(对齐 rail.dart:系统只保留 概览 + 关系图谱)。

// AI 与 灵感 两组对所有项目类型是同一份 —— rail.dart 里也是同两组,
// 普通 novel 与剧本共用,别在两处各写一份。
const AI_SECTION = {
  label: "AI",
  items: [
    { id: "chat", icon: "chats", label: "聊天" },
    { id: "rules", icon: "shield", label: "智能体规则" },
  ],
};

const INSPIRATION_SECTION = {
  label: "灵感",
  items: [
    { id: "council", icon: "users-four", label: "圆桌会议" },
    { id: "monologue", icon: "user", label: "独白" },
    { id: "theater", icon: "film-strip", label: "小剧场" },
    { id: "roleplay", icon: "chat-centered", label: "角色扮演" },
  ],
};

// 世界观也是共用的一组 —— 剧本同样要设定、地点和道具/势力图鉴,
// 没有理由和小说长得不一样。势力/生物/物品/技能在 rail.dart 里已并进「图鉴」。
const WORLD_SECTION = {
  label: "世界观",
  items: [
    { id: "world", icon: "globe-simple", label: "设定" },
    { id: "map", icon: "map-trifold", label: "地图" },
    { id: "compendium", icon: "package", label: "图鉴" },
  ],
};

// 剧本型 novel(novel.screenplay)只换「创作」一组 ——
// 剧本的创作单元是场次/节拍,不是章节/伏笔;其余四组与普通 novel 同一份。
// 图标不得在表内重复(折叠态只剩图标)。
const SCREENPLAY_SECTIONS = [
  {
    label: "系统",
    items: [
      { id: "overview", icon: "grid-nine", label: "概览" },
      { id: "relations", icon: "tree-structure", label: "关系图谱" },
      { id: "progress", icon: "trend-up", label: "当前进度" },
      { id: "canvas", icon: "frame-corners", label: "画布", href: "canvas/Canvas.html?from=editor" },
      { id: "cover", icon: "palette", label: "封面" },
    ],
  },
  {
    label: "创作",
    items: [
      { id: "script", icon: "file-text", label: "剧本" },
      { id: "outline", icon: "list-numbers", label: "大纲" },
      { id: "beat", icon: "path", label: "节拍" },
      { id: "scenes", icon: "squares-four", label: "场次" },
      { id: "characters", icon: "users", label: "人物" },
      // 制片(短剧制作方案)：app 内页面(NavRail + 第二栏照常)，片段 | 画布两个视图；片段是画布上带场次的视频节点。剧本里不放制作界面。
      { id: "production", icon: "film-strip", label: "制片", href: "drama/Drama.html?from=editor" },
      { id: "materials", icon: "folder-simple-star", label: "素材" },
    ],
  },
  WORLD_SECTION,
  AI_SECTION,
  INSPIRATION_SECTION,
];

const NAV_SECTIONS = [
  {
    label: "系统",
    items: [
      { id: "overview", icon: "grid-nine", label: "概览" },
      { id: "graph", icon: "tree-structure", label: "关系图谱" },
      { id: "progress", icon: "trend-up", label: "当前进度" },
      // 画布是独立路由页(CanvasEditorPage),不在编辑器内联 ——
      // 只有停在这一页时才注入 canvas 工具,别的页面 agent 不带这 7 个工具。
      { id: "canvas", icon: "frame-corners", label: "画布", href: "canvas/Canvas.html?from=editor" },
      { id: "cover", icon: "image-square", label: "封面" },
    ],
  },
  {
    label: "创作",
    items: [
      { id: "chapters", icon: "book-open", label: "章节" },
      { id: "outline", icon: "list-numbers", label: "大纲" },
      { id: "characters", icon: "users", label: "人物" },
      { id: "foreshadowing", icon: "flag-pennant", label: "伏笔" },
      { id: "materials", icon: "folder-simple-star", label: "素材" },
    ],
  },
  WORLD_SECTION,
  AI_SECTION,
  INSPIRATION_SECTION,
];

// 折叠 / 展开侧栏的图标,对齐 Flutter assets/icons/collapse.svg(不是 phosphor,用 mask 上色)。
function SidebarCollapseIcon({ base = "", size = 18, color = "var(--text-muted)" }) {
  const url = `url(${base}assets/icons/collapse.svg)`;
  return (
    <span aria-hidden="true" style={{ display: "inline-block", flex: "none", width: size, height: size, backgroundColor: color,
      WebkitMaskImage: url, maskImage: url, WebkitMaskSize: "contain", maskSize: "contain",
      WebkitMaskRepeat: "no-repeat", maskRepeat: "no-repeat", WebkitMaskPosition: "center", maskPosition: "center" }} />
  );
}

// hrefBase:子目录页面(如 drama/)复用这条导航时,给 href 和图标补相对前缀。
// collapsed:对齐 Flutter LeftSidebar 折叠态 —— 整个左侧栏缩成 48px 图标栏(第二栏由页面隐藏),
// 第一格是 accent 色的展开按钮,底部个人资料入口只留头像。
function NavRail({ activeId, onSelect, onOpenSettings, screenplay, hrefBase = "", collapsed, onExpand }) {
  const sections = screenplay ? SCREENPLAY_SECTIONS : NAV_SECTIONS;
  return (
    <nav className={"m-navrail" + (collapsed ? " m-navrail--collapsed" : "")}>
      {collapsed && (
        <button type="button" className="m-navrail__row m-navrail__expand" title="展开侧栏" onClick={onExpand}>
          <SidebarCollapseIcon base={hrefBase} color="var(--accent)" />
        </button>
      )}
      <div className="m-navrail__scroll">
        {sections.map((sec, i) => (
          <div key={sec.label} className="m-navrail__sec">
            {/* 组间分割线 —— rail.dart 在每两组之间画一条,两端各缩进 sm。 */}
            {i > 0 && <div className="m-navrail__sec-div" />}
            <div className="m-navrail__sec-label">{sec.label}</div>
            <div className="m-navrail__sec-items">
              {sec.items.map((it) => (
                <button
                  key={it.id}
                  type="button"
                  className={
                    "m-navrail__row" +
                    (activeId === it.id ? " is-active" : "")
                  }
                  onClick={() =>
                    it.href ? (window.location.href = hrefBase + it.href) : onSelect(it.id)
                  }
                  title={collapsed ? it.label : undefined}
                >
                  <Icon name={it.icon} size={16} />
                  <span>{it.label}</span>
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
      <button
        type="button"
        className="m-navrail__brand"
        onClick={onOpenSettings}
        title="设置 · 幻界"
      >
        <span className="m-avatar m-avatar--user" style={{ width: 22, height: 22 }}>
          <Icon name="user" size={12} />
        </span>
        <span className="m-navrail__brand-name">幻界</span>
      </button>
    </nav>
  );
}

Object.assign(window, { NavRail, SidebarCollapseIcon });
